#include "local_api.h"
#include "device_console.h"
#include <IPAddress.h>
#include "config.h"
#include "local_network.h"
#include "memory_diagnostics.h"
#include "runtime_diagnostics.h"
#include "web_origin.h"

void LocalApi::headers() {
  if (!config::relayEnabled) server_.sendHeader("Access-Control-Allow-Origin", "*");
  else if (web_origin::allowed(server_.header("Origin").c_str(), config::allowedWebOrigins,
                              sizeof(config::allowedWebOrigins) / sizeof(config::allowedWebOrigins[0]))) {
    server_.sendHeader("Access-Control-Allow-Origin", server_.header("Origin"));
    server_.sendHeader("Vary", "Origin");
  }
  server_.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server_.sendHeader("Access-Control-Allow-Headers", "Content-Type, X-LockLink-Nonce, X-LockLink-Signature");
  server_.sendHeader("Cache-Control", "no-store");
}

void LocalApi::json(int status, const String& body) { headers(); server_.send(status, "application/json", body); }

void LocalApi::begin() {
  const char* names[] = {"Origin", "X-LockLink-Nonce", "X-LockLink-Signature"};
  server_.collectHeaders(names, 3);
  server_.on("/status", HTTP_GET, [this]() {
    const auto memory = memory_diagnostics::snapshot();
    const auto runtime = runtime_diagnostics::snapshot();
    const auto events = local_network::diagnostics();
    char temperature[16] = "null", peak[16] = "null";
    if (runtime.temperatureAvailable) {
      snprintf(temperature, sizeof(temperature), "%.1f", runtime.temperature);
      snprintf(peak, sizeof(peak), "%.1f", runtime.maximumTemperature);
    }
    char body[768];
    const int length = snprintf(body, sizeof(body),
        "{\"online\":true,\"device\":\"LockLink\",\"state\":\"%s\",\"mode\":\"%s\",\"armed\":%s,"
        "\"firmware_version\":\"%s\",\"physical_state_known\":false,"
        "\"health\":{\"boot\":\"%s\",\"uptime_s\":%lu,\"reset_reason\":%lu,\"free_heap\":%u,\"min_heap\":%u,\"largest_block\":%u,"
        "\"allocation_failures\":%lu,\"wifi_disconnects\":%lu,\"wifi_last_reason\":%u,"
        "\"chip_temperature_c\":%s,\"chip_peak_c\":%s,\"temperature_failures\":%lu,\"max_loop_gap_ms\":%lu,"
        "\"stack_min_bytes\":%lu,\"http_rejected\":%lu,\"http_timeouts\":%lu}}",
        output_.active() ? "unlocking" : "locked", config::relayEnabled ? "relay" : "led",
        !config::relayEnabled || auth_.ready() ? "true" : "false", config::version, runtime_diagnostics::bootId(),
        (unsigned long)runtime.uptimeSeconds, (unsigned long)runtime.resetReason,
        (unsigned)memory.free, (unsigned)memory.minimum, (unsigned)memory.largest,
        (unsigned long)memory.allocationFailures, (unsigned long)events.disconnects, events.lastDisconnectReason,
        temperature, peak, (unsigned long)runtime.temperatureFailures, (unsigned long)runtime.maxLoopGapMs,
        (unsigned long)runtime.loopStackMinimum,
        (unsigned long)server_.rejectedRequests(), (unsigned long)server_.receiveTimeouts());
    if (length < 0 || size_t(length) >= sizeof(body)) { json(503, "{\"error\":\"device_busy\"}"); return; }
    headers(); server_.setContentLength(length); server_.send(200, "application/json", "");
    server_.sendContent(body, size_t(length));
  });
  server_.on("/challenge", HTTP_GET, [this]() {
    if (!auth_.ready()) { json(503, "{\"error\":\"relay_not_armed\"}"); return; }
    const String nonce = auth_.issueChallenge(millis());
    if (nonce.isEmpty()) { json(503, "{\"error\":\"device_busy\"}"); return; }
    json(200, String("{\"nonce\":\"") + nonce + "\"}");
  });
  server_.on("/unlock", HTTP_POST, [this]() {
    if (config::relayEnabled) {
      if (!auth_.ready()) { json(503, "{\"error\":\"relay_not_armed\"}"); return; }
      if (!auth_.verify(server_.header("X-LockLink-Nonce"), server_.header("X-LockLink-Signature"), millis())) {
        json(401, "{\"error\":\"unauthorized\"}"); return;
      }
    }
    const auto result = output_.release();
    if (result == ReleaseOutput::Result::busy) json(409, "{\"success\":false,\"error\":\"already_unlocking\"}");
    else if (result != ReleaseOutput::Result::started) json(503, "{\"error\":\"output_unavailable\"}");
    else json(200, "{\"success\":true,\"state\":\"unlocking\",\"duration_ms\":1500}");
  });
  for (const char* path : {"/status", "/challenge", "/unlock"}) {
    server_.on(path, HTTP_OPTIONS, [this]() { headers(); server_.send(204); });
  }
  server_.onNotFound([this]() { json(404, "{\"error\":\"not_found\"}"); });
}

void LocalApi::poll() {
  const auto network = local_network::snapshot();
  // A missed disconnect/rejoin or DHCP change invalidates listening sockets.
  if (listening_ && (network.epoch != networkEpoch_ || network.ipv4 != address_)) {
    server_.stop(); listening_ = false;
  }
  if (network.ready()) {
    if (!listening_) {
      server_.begin(); listening_ = true;
      networkEpoch_ = network.epoch; address_ = network.ipv4;
      console.print("LockLink app address: "); console.println(IPAddress(network.ipv4));
    }
    server_.handleClient();
  } else if (listening_) {
    server_.stop(); listening_ = false;
    console.println("App connection paused: waiting for Wi-Fi and an IPv4 address.");
  }
}
