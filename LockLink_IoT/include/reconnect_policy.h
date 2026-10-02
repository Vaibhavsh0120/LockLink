#pragma once
#include <stdint.h>

class ReconnectPolicy {
 public:
  bool due(uint32_t now, bool ready) {
    if (ready) {
      last_ = now;
      delay_ = 5000;
      return false;
    }
    if (uint32_t(now - last_) < delay_) return false;
    last_ = now;
    delay_ = delay_ < 15000 ? delay_ * 2 : 30000;
    return true;
  }
 private:
  uint32_t last_ = 0, delay_ = 5000;
};
