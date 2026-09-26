#include "local_api.h"
#include <IPAddress.h>
#include "config.h"
#include "local_network.h"

void LocalApi::headers() {
  if (!config::relayEnabled) {
    server_.sendHeader("Access-Control-Allow-Origin", "*");
  } else if (config::allowedWebOrigin[0] != '\0' &&
             server_.header("Origin") == config::allowedWebOrigin) {
    server_.sendHeader("Access-Control-Allow-Origin", config::allowedWebOrigin);
    server_.sendHeader("Vary", "Origin");
  }
  server_.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server_.sendHeader("Access-Control-Allow-Headers",
      "Content-Type, X-LockLink-Nonce, X-LockLink-Signature");
  server_.sendHeader("Cache-Control", "no-store");
}

void LocalApi::json(int status, const String& body) {
  headers();
  server_.send(status, "application/json", body);
}

void LocalApi::begin() {
  const char* names[] = {"Origin", "X-LockLink-Nonce", "X-LockLink-Signature"};
  server_.collectHeaders(names, 3);
  server_.on("/status", HTTP_GET, [this]() {
    json(200, String("{\"online\":true,\"device\":\"LockLink\",\"state\":\"") +
         (output_.active() ? "unlocking" : "locked") + "\",\"mode\":\"" +
         (config::relayEnabled ? "relay" : "led") + "\",\"armed\":" +
         (!config::relayEnabled || auth_.ready() ? "true" : "false") +
         ",\"matter_accessory\":\"momentary_switch\",\"physical_state_known\":false}");
  });
  server_.on("/challenge", HTTP_GET, [this]() {
    if (!auth_.ready()) {
      json(503, "{\"error\":\"relay_not_armed\"}");
      return;
    }
    json(200, String("{\"nonce\":\"") + auth_.issueChallenge(millis()) + "\"}");
  });
  server_.on("/unlock", HTTP_POST, [this]() {
    if (config::relayEnabled) {
      if (!auth_.ready()) {
        json(503, "{\"error\":\"relay_not_armed\"}");
        return;
      }
      if (!auth_.verify(server_.header("X-LockLink-Nonce"),
                        server_.header("X-LockLink-Signature"), millis())) {
        json(401, "{\"error\":\"unauthorized\"}");
        return;
      }
    }
    const auto result = output_.release();
    if (result == ReleaseOutput::Result::busy) {
      json(409, "{\"success\":false,\"error\":\"already_unlocking\"}");
    } else if (result != ReleaseOutput::Result::started) {
      json(503, "{\"error\":\"output_unavailable\"}");
    } else {
      json(200, "{\"success\":true,\"state\":\"unlocking\",\"duration_ms\":2000}");
    }
  });
  for (const char* path : {"/status", "/challenge", "/unlock"}) {
    server_.on(path, HTTP_OPTIONS, [this]() { headers(); server_.send(204); });
  }
  server_.onNotFound([this]() { json(404, "{\"error\":\"not_found\"}"); });
}

void LocalApi::poll() {
  // Matter creates the ESP-IDF interface; Arduino's WiFi.status() cache is not
  // initialized on this path. Observe the real interface without WiFi.begin().
  const auto network = local_network::snapshot();
  if (network.ready()) {
    if (!listening_) {
      server_.begin();
      listening_ = true;
      Serial.print("LockLink app address: ");
      Serial.println(IPAddress(network.ipv4));
    }
    server_.handleClient();
  } else if (listening_) {
    server_.stop();
    listening_ = false;
    Serial.println("App connection paused: waiting for Wi-Fi and an IPv4 address.");
  }
}

void LocalApi::printStatus() {
  const auto network = local_network::snapshot();
  Serial.print("App HTTP: ");
  if (network.ready() && listening_) {
    Serial.print("http://");
    Serial.println(IPAddress(network.ipv4));
  } else {
    Serial.println("waiting for Wi-Fi / IPv4 (pair in Home if not yet paired).");
  }
}
