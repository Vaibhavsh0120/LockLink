#pragma once
#include <cstdint>
#include "config.h"

// Commanded release state only; there is no physical door-position sensor.
// The caller serializes access and supplies a monotonic millisecond clock.
class LockState {
 public:
  bool active() const { return active_; }
  bool unlock(uint32_t now) {
    if (active_) return false;
    started_ = now;
    active_ = true;
    return true;
  }
  void lock() { active_ = false; }
  bool expire(uint32_t now) {
    if (!active_ || uint32_t(now - started_) < matter_config::pulseMs) return false;
    active_ = false;
    return true;
  }

 private:
  bool active_ = false;
  uint32_t started_ = 0;
};
