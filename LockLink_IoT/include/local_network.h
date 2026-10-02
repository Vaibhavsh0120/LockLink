#pragma once
#include <cstdint>

namespace local_network {
// Configure a bounded packet budget before app_network starts Wi-Fi.
// Does not start, connect, or change credentials.
bool prepareBuffers();
// Observe the existing event loop without reconnecting from callbacks.
bool beginDiagnostics();
struct Diagnostics {
  uint32_t epoch = 0;
  uint32_t disconnects = 0;
  uint16_t lastDisconnectReason = 0;
};
Diagnostics diagnostics();
struct Snapshot {
  bool linkUp = false;
  uint32_t ipv4 = 0;
  uint32_t epoch = 0;
  bool ready() const { return linkUp && ipv4 != 0; }
};
// Read the live interface and disable modem sleep once ready (and on reconnect),
// without starting another Wi-Fi manager.
Snapshot snapshot();
}
