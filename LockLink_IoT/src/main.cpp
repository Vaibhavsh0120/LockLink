#include <Arduino.h>
#include <WebServer.h>
#include <WiFi.h>

#include "config.h"
#include "lock_output.h"

LockOutput lockOutput;
WebServer server(config::serverPort);
uint32_t lastWifiAttemptMs = 0;
bool wifiAttempted = false;
bool serverStarted = false;
uint32_t lastStatusLogMs = 0;

void addCorsHeaders() {
  // Browser support for the local LED prototype only. Add authentication and
  // an origin policy before this firmware ever controls a real door lock.
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
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
        (lockOutput.isUnlocking() ? "unlocking" : "locked") + "\"}");
  });
  server.on("/unlock", HTTP_POST, []() {
    if (!lockOutput.startPulse(millis())) {
      sendJson(409, "{\"success\":false,\"error\":\"already_unlocking\"}");
      return;
    }
    Serial.println("Unlock pulse started");
    sendJson(200, String("{\"success\":true,\"state\":\"unlocking\",\"duration_ms\":") +
        config::unlockDurationMs + "}");
  });
  server.on("/status", HTTP_OPTIONS, []() { addCorsHeaders(); server.send(204); });
  server.on("/unlock", HTTP_OPTIONS, []() { addCorsHeaders(); server.send(204); });
  server.onNotFound([]() {
    sendJson(404, "{\"error\":\"not_found\"}");
  });
}

void setup() {
  Serial.begin(115200);
  lockOutput.begin();
  Serial.printf("Test output: %s on GPIO %u\n",
      config::outputDriver == config::OutputDriver::addressableRgb
          ? "built-in RGB LED" : "digital output", config::outputPin);
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
      Serial.print("LockLink ready at http://");
      Serial.println(WiFi.localIP());
    }
    server.handleClient();
  } else if (serverStarted) {
    server.stop();
    serverStarted = false;
    Serial.println("Wi-Fi lost; retrying");
  }
  // Monitor may open after boot; repeat the connection details for diagnostics.
  if (uint32_t(nowMs - lastStatusLogMs) >= 15000) {
    lastStatusLogMs = nowMs;
    if (WiFi.status() == WL_CONNECTED) {
      Serial.print("LockLink online at http://");
      Serial.print(WiFi.localIP());
    } else {
      Serial.print("LockLink offline");
    }
    Serial.println(lockOutput.isUnlocking() ? " | LED on" : " | LED off");
  }
  delay(2);
}
