#include "lock_output.h"
#include "config.h"

void LockOutput::begin() {
  if (config::outputDriver == config::OutputDriver::addressableRgb) {
    neopixelWrite(config::outputPin, 0, 0, 0);
    return;
  }
  // Set the inactive level before enabling the output to avoid a startup pulse.
  digitalWrite(config::outputPin, config::outputActiveHigh ? LOW : HIGH);
  pinMode(config::outputPin, OUTPUT);
}

void LockOutput::setActive(bool active) {
  if (config::outputDriver == config::OutputDriver::addressableRgb) {
    neopixelWrite(config::outputPin, 0, active ? 32 : 0, 0);
    return;
  }
  digitalWrite(config::outputPin,
      (active == config::outputActiveHigh) ? HIGH : LOW);
}

bool LockOutput::startPulse(uint32_t nowMs) {
  if (unlocking_) return false;
  startedAtMs_ = nowMs;
  unlocking_ = true;
  setActive(true);
  return true;
}

void LockOutput::update(uint32_t nowMs) {
  if (unlocking_ && uint32_t(nowMs - startedAtMs_) >= config::unlockDurationMs) {
    setActive(false);
    unlocking_ = false;
  }
}
