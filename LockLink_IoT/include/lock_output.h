#pragma once
#include <Arduino.h>

class LockOutput {
 public:
  void begin();
  bool startPulse(uint32_t nowMs);
  void update(uint32_t nowMs);
  bool isUnlocking() const { return unlocking_; }

 private:
  void setActive(bool active);
  bool unlocking_ = false;
  uint32_t startedAtMs_ = 0;
};
