#pragma once
#include <cstdint>
#include <cassert>
constexpr int LOW = 0, HIGH = 1, OUTPUT = 1;
extern int relayLevel;
extern int indicatorLevel;
extern bool relayOutputEnabled, indicatorOutputEnabled;
inline void digitalWrite(uint8_t pin, int level) {
  if (pin == 4) { assert(relayOutputEnabled); relayLevel = level; }
  if (pin == 8) { assert(indicatorOutputEnabled); indicatorLevel = level; }
}
inline void pinMode(uint8_t pin, int mode) {
  assert(mode == OUTPUT);
  // Establish inactive levels before enabling either output driver.
  if (pin == 4) { assert(relayLevel == HIGH); relayOutputEnabled = true; }
  if (pin == 8) { assert(indicatorLevel == HIGH); indicatorOutputEnabled = true; }
}
