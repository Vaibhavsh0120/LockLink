#pragma once
#include <stddef.h>
#include <stdint.h>

namespace memory_diagnostics {
struct Snapshot {
  size_t free = 0;
  size_t minimum = 0;
  size_t largest = 0;
  uint32_t allocationFailures = 0;
  size_t lastFailedBytes = 0;
};
bool begin();
Snapshot snapshot();
}
