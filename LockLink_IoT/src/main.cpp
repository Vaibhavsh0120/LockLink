#include <Arduino.h>
#include <WebServer.h>
#include <WiFi.h>

#include "config.h"
#include "lock_output.h"
#include "unlock_auth.h"

LockOutput lockOutput;
UnlockAuth unlockAuth;
WebServer server(config::serverPort);
uint32_t lastWifiAttemptMs = 0;
bool wifiAttempted = false;
bool serverStarted = false;

void logConnectionDetails() {
  Serial.print("LockLink ready at http://");
  Serial.println(WiFi.localIP());

  const String key(config::unlockKeyHex);
  bool validKey = key.length() == 64;
  for (size_t i = 0; validKey && i < key.length(); ++i) {
    const char c = key[i];
    validKey = (c >= '0' && c <= '9') ||
        (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
  }
  if (!validKey) {
    Serial.println("App pairing key: unavailable; configure LOCKLINK_UNLOCK_KEY_HEX");
    return;
  }

  Serial.print("App pairing key: ");
  if (key.equalsIgnoreCase(
      "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4")) {
    Serial.println("1234");
  } else {
    // The app accepts a configured 64-character hex key directly.
    Serial.println(key);
  }
}

void addCorsHeaders() {
  if (config::relayEnabled) {
    const String origin = server.header("Origin");
    if (config::allowedWebOrigin[0] != '\0' &&
        origin == config::allowedWebOrigin) {
      server.sendHeader("Access-Control-Allow-Origin", origin);
      server.sendHeader("Vary", "Origin");
    }
  } else {
    server.sendHeader("Access-Control-Allow-Origin", "*");
  }
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers",
      "Content-Type, X-LockLink-Nonce, X-LockLink-Signature");
  server.sendHeader("Cache-Control", "no-store");
}

void sendJson(int code, const String& body) {
  addCorsHeaders();
  server.send(code, "application/json", body);
}

void connectWifi(uint32_t nowMs) {
  if (config::wifiSsid[0] == '\0') return;
  if (WiFi.status() == WL_CONNECTED) return;
  if (wifiAttempted && uint32_t(nowMs - lastWifiAttemptMs) < config::wifiRetryMs) return;
  wifiAttempted = true;
  lastWifiAttemptMs = nowMs;
  Serial.println("Connecting to Wi-Fi...");
  WiFi.disconnect();
  WiFi.begin(config::wifiSsid, config::wifiPassword);
}

void setupRoutes() {
  server.on("/status", HTTP_GET, []() {
    sendJson(200, String("{\"online\":true,\"device\":\"LockLink\",\"state\":\"") +
        (lockOutput.isUnlocking() ? "unlocking" : "locked") +
        "\",\"mode\":\"" + (config::relayEnabled ? "relay" : "led") +
        "\",\"armed\":" + (config::relayEnabled
            ? (unlockAuth.ready() ? "true" : "false") : "true") + "}");
  });
  server.on("/challenge", HTTP_GET, []() {
    if (!unlockAuth.ready()) {
      sendJson(503, "{\"error\":\"relay_not_armed\"}");
      return;
    }
    sendJson(200, String("{\"nonce\":\"") +
        unlockAuth.issueChallenge(millis()) + "\"}");
  });
  server.on("/unlock", HTTP_POST, []() {
    if (config::relayEnabled) {
      if (!unlockAuth.ready()) {
        sendJson(503, "{\"error\":\"relay_not_armed\"}");
        return;
      }
      if (!unlockAuth.verify(server.header("X-LockLink-Nonce"),
          server.header("X-LockLink-Signature"), millis())) {
        sendJson(401, "{\"error\":\"unauthorized\"}");
        return;
      }
    }
    if (!lockOutput.startPulse(millis())) {
      sendJson(409, "{\"success\":false,\"error\":\"already_unlocking\"}");
      return;
    }
    Serial.println("Unlock pulse started");
    sendJson(200, String("{\"success\":true,\"state\":\"unlocking\",\"duration_ms\":") +
        config::unlockDurationMs + "}");
  });
  server.on("/status", HTTP_OPTIONS, []() { addCorsHeaders(); server.send(204); });
  server.on("/challenge", HTTP_OPTIONS, []() { addCorsHeaders(); server.send(204); });
  server.on("/unlock", HTTP_OPTIONS, []() { addCorsHeaders(); server.send(204); });
  server.onNotFound([]() {
    sendJson(404, "{\"error\":\"not_found\"}");
  });
}

void setup() {
  Serial.begin(115200);
  lockOutput.begin();
  const char* requestHeaders[] = {
      "Origin", "X-LockLink-Nonce", "X-LockLink-Signature"};
  server.collectHeaders(requestHeaders, 3);
  if (config::relayEnabled) {
    Serial.printf("Relay output: GPIO %u (active HIGH); indicator: GPIO %u\n",
        config::outputPin, config::indicatorPin);
    if (!unlockAuth.begin()) {
      Serial.println("Relay NOT armed: set a 64-character hex unlock key");
    }
  } else {
    Serial.printf("LED prototype: GPIO %u\n", config::indicatorPin);
  }
  WiFi.mode(WIFI_STA);
  setupRoutes();
  if (config::wifiSsid[0] == '\0') {
    Serial.println("Set Wi-Fi credentials in include/private_config.h");
  } else {
    connectWifi(millis());
  }
}

void loop() {
  const uint32_t nowMs = millis();
  lockOutput.update(nowMs);
  connectWifi(nowMs);
  if (WiFi.status() == WL_CONNECTED) {
    if (!serverStarted) {
      server.begin();
      serverStarted = true;
      logConnectionDetails();
    }
    server.handleClient();
  } else if (serverStarted) {
    server.stop();
    serverStarted = false;
    Serial.println("Wi-Fi lost; retrying");
  }
  delay(2);
}
