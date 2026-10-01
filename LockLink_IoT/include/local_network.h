#pragma once
#include <cstdint>

namespace local_network {
// Configure the driver's bounded memory budget before Matter starts Wi-Fi.
// Does not start, connect, or change credentials; Matter owns that lifecycle.
bool prepareBuffers();
struct Snapshot {
  bool linkUp = false;
  uint32_t ipv4 = 0;
  bool ready() const { return linkUp && ipv4 != 0; }
};
// Read Matter's interface and disable modem sleep once ready (and on reconnect),
// without starting another Wi-Fi manager.
Snapshot snapshot();
}
