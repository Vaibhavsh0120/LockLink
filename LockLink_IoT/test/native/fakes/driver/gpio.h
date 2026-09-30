#pragma once
#include <Arduino.h>
using gpio_num_t = uint8_t;
inline int gpio_set_level(gpio_num_t pin, int level) {
  if (pin == 4) relayLevel = level;
  if (pin == 8) indicatorLevel = level;
  return 0;
}
