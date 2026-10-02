#pragma once
#include <stdint.h>

namespace runtime_diagnostics {
struct Snapshot {
  uint32_t uptimeSeconds = 0;
  uint32_t resetReason = 0;
  uint32_t maxLoopGapMs = 0;
  uint32_t loopStackMinimum = 0;
  float temperature = 0;
  float maximumTemperature = 0;
  bool temperatureAvailable = false;
  uint32_t temperatureFailures = 0;
};
bool begin();
void poll();
Snapshot snapshot();
const char* bootId();
}
