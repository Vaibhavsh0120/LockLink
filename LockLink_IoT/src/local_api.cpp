#include "local_api.h"
#include "device_console.h"
#include "terminal_commands.h"
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
  terminalAuth_.begin();
  const char* names[] = {"Origin", "X-LockLink-Nonce", "X-LockLink-Signature"};
  server_.collectHeaders(names, 3);
  server_.on("/status", HTTP_GET, [this]() {
    json(200, String("{\"online\":true,\"device\":\"LockLink\",\"state\":\"") +
         (output_.active() ? "unlocking" : "locked") + "\",\"mode\":\"" +
         (config::relayEnabled ? "relay" : "led") + "\",\"armed\":" +
         (!config::relayEnabled || auth_.ready() ? "true" : "false") +
         ",\"firmware_version\":\"" + config::version +
         "\",\"matter_accessory\":\"door_lock\",\"physical_state_known\":false}");
  });
  server_.on("/challenge", HTTP_GET, [this]() {
    if (!auth_.ready()) {
      json(503, "{\"error\":\"relay_not_armed\"}");
      return;
    }
    const String nonce = auth_.issueChallenge(millis());
    if (nonce.isEmpty()) { json(503, "{\"error\":\"device_busy\"}"); return; }
    json(200, String("{\"nonce\":\"") + nonce + "\"}");
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
      json(200, "{\"success\":true,\"state\":\"unlocking\",\"duration_ms\":" +
           String(matter_config::pulseMs) + "}");
    }
  });
  server_.on("/terminal/challenge", HTTP_GET, [this]() {
    if (!terminalAuth_.ready()) {
      json(503, "{\"error\":\"terminal_key_missing\"}");
      return;
    }
    const String nonce = terminalAuth_.issueChallenge(millis());
    if (nonce.isEmpty()) { json(503, "{\"error\":\"terminal_busy\"}"); return; }
    json(200, String("{\"nonce\":\"") + nonce + "\"}");
  });
  server_.on("/terminal", HTTP_POST, [this]() { terminalRequest(); });
  for (const char* path : {"/status", "/challenge", "/unlock", "/terminal/challenge", "/terminal"}) {
    server_.on(path, HTTP_OPTIONS, [this]() { headers(); server_.send(204); });
  }
  server_.onNotFound([this]() { json(404, "{\"error\":\"not_found\"}"); });
}

void LocalApi::terminalRequest() {
  if (!terminalAuth_.ready()) {
    json(503, "{\"error\":\"terminal_key_missing\"}");
    return;
  }
  const String command = server_.arg("plain");
  const String after = server_.arg("after");
  const String boot = server_.arg("boot");
  bool valid = command.length() <= 128 && after.length() > 0 && after.length() <= 10 && boot.length() <= 16;
  for (size_t i = 0; i < command.length(); ++i) valid &= command[i] >= 32 && command[i] <= 126;
  for (size_t i = 0; i < after.length(); ++i) valid &= isDigit(after[i]);
  for (size_t i = 0; i < boot.length(); ++i) valid &= isHexadecimalDigit(boot[i]);
  const uint64_t cursor = strtoull(after.c_str(), nullptr, 10);
  valid &= cursor <= UINT32_MAX;
  if (!valid) { json(400, "{\"error\":\"invalid_request\"}"); return; }
  const String action = String("terminal:") + after + ':' + boot + ':' + command;
  if (!terminalAuth_.verify(server_.header("X-LockLink-Nonce"),
                            server_.header("X-LockLink-Signature"), millis(), action)) {
    json(401, "{\"error\":\"unauthorized\"}");
    return;
  }
  const String logs = console.snapshot(uint32_t(cursor), boot);
  if (logs.isEmpty()) { json(503, "{\"error\":\"terminal_busy\"}"); return; }
  // Check log availability before executing a command that can change pairings.
  const auto reply = terminalCommand(command, output_, auth_);
  json(200, String("{") + logs + ",\"ok\":" + (reply.ok ? "true" : "false") +
      ",\"commissioned\":" + (reply.commissioned ? "true" : "false") +
      ",\"homes\":" + reply.homesJson + ",\"fabric_capacity\":" + reply.fabricCapacity +
      ",\"pairing_window_open\":" + (reply.pairingWindowOpen ? "true" : "false") +
      ",\"pairing_mode\":" + (reply.additionalPairing ? "\"additional\"" : "null") +
      ",\"pairing_window_id\":" + (reply.pairingWindowId.isEmpty() ? String("null") : jsonQuote(reply.pairingWindowId)) +
      ",\"output\":" + jsonQuote(reply.output) + ",\"pairing_code\":" +
      (reply.pairingCode.isEmpty() ? String("null") : jsonQuote(reply.pairingCode)) +
      ",\"pairing_qr_payload\":" +
      (reply.pairingQrPayload.isEmpty() ? String("null") : jsonQuote(reply.pairingQrPayload)) + '}');
}

void LocalApi::poll() {
  // Matter creates the ESP-IDF interface; Arduino's WiFi.status() cache is not
  // initialized on this path. Observe the real interface without WiFi.begin().
  const auto network = local_network::snapshot();
  if (network.ready()) {
    if (!listening_) {
      server_.begin();
      listening_ = true;
      console.print("LockLink app address: ");
      console.println(IPAddress(network.ipv4));
    }
    server_.handleClient();
  } else if (listening_) {
    server_.stop();
    listening_ = false;
    console.println("App connection paused: waiting for Wi-Fi and an IPv4 address.");
  }
}
