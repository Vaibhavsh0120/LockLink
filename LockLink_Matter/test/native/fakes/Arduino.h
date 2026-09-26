#pragma once
#include <cstdint>
constexpr int LOW = 0, HIGH = 1, OUTPUT = 1;
extern int relayLevel;
extern int indicatorGreen;
inline void digitalWrite(uint8_t pin, int level) { if (pin == 2) relayLevel = level; }
inline void pinMode(uint8_t, int) {}
inline void rgbLedWrite(uint8_t, int, int green, int) { indicatorGreen = green; }
