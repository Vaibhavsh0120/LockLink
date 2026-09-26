#pragma once
#include <cstdint>

namespace local_network {
struct Snapshot {
  bool linkUp = false;
  uint32_t ipv4 = 0;
  bool ready() const { return linkUp && ipv4 != 0; }
};
// Read the interface created by Matter, without starting another Wi-Fi manager.
Snapshot snapshot();
}
