#include "local_api.h"
#include "device_console.h"
#include "terminal_commands.h"
#include <IPAddress.h>
#include "config.h"
#include "local_network.h"
#include "json_writer.h"

namespace {
template <typename Writer>
bool terminalBody(Writer& writer, const String& logs, const TerminalReply& reply) {
  writer.raw("{"); writer.raw(logs.c_str(), logs.length());
  writer.raw(",\"ok\":"); writer.raw(reply.ok ? "true" : "false");
  writer.raw(",\"commissioned\":"); writer.raw(reply.commissioned ? "true" : "false");
  writer.raw(",\"homes\":"); writer.raw(reply.homesJson.c_str(), reply.homesJson.length());
  writer.raw(",\"fabric_capacity\":"); writer.number(reply.fabricCapacity);
  writer.raw(",\"pairing_window_open\":"); writer.raw(reply.pairingWindowOpen ? "true" : "false");
  writer.raw(",\"pairing_mode\":"); writer.raw(reply.additionalPairing ? "\"additional\"" : "null");
  const auto nullable = [&](const String& value) {
    if (value.isEmpty()) writer.raw("null");
    else writer.quote(value.c_str(), value.length());
  };
  writer.raw(",\"pairing_window_id\":"); nullable(reply.pairingWindowId);
  writer.raw(",\"output\":"); writer.quote(reply.output.c_str(), reply.output.length());
  writer.raw(",\"pairing_code\":"); nullable(reply.pairingCode);
  writer.raw(",\"pairing_qr_payload\":"); nullable(reply.pairingQrPayload);
  writer.raw("}"); return writer.finish();
}
}

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
  // Serialize through a fixed stack buffer instead of allocating a second
  // whole response while logs and command output still occupy the heap.
  size_t length = 0;
  JsonWriter counter([&](const char*, size_t size) { length += size; return true; });
  terminalBody(counter, logs, reply);
  headers();
  server_.setContentLength(length);
  server_.send(200, "application/json", "");
  JsonWriter writer([&](const char* data, size_t size) {
    // Content-Length is explicit, so no HTTP chunk framing is needed. The
    // WebServer sendContent API hides short writes; check the client directly.
    return server_.client().write(reinterpret_cast<const uint8_t*>(data), size) == size;
  });
  if (!terminalBody(writer, logs, reply)) server_.client().stop();
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
