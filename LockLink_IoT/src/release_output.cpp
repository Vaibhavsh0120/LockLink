#include "release_output.h"
#include "config.h"

namespace {
uint32_t nowMs() { return static_cast<uint32_t>(esp_timer_get_time() / 1000); }
}

bool ReleaseOutput::begin() {
  // Inactive output is established before any network or commissioning work.
  if (config::relayEnabled) {
    digitalWrite(config::outputPin, config::outputActiveHigh ? LOW : HIGH);
    pinMode(config::outputPin, OUTPUT);
  }
  rgbLedWrite(config::indicatorPin, 0, 0, 0);
  mutex_ = xSemaphoreCreateMutex();
  if (!mutex_) return false;
  esp_timer_create_args_t args = {};
  args.callback = timerCallback;
  args.arg = this;
  args.dispatch_method = ESP_TIMER_TASK;
  args.name = "door_release";
  enabled_ = esp_timer_create(&args, &timer_) == ESP_OK;
  return enabled_;
}

void ReleaseOutput::setRelay(bool enabled) {
  if (config::relayEnabled) {
    digitalWrite(config::outputPin,
                 enabled == config::outputActiveHigh ? HIGH : LOW);
  }
}

ReleaseOutput::Result ReleaseOutput::release() {
  if (!mutex_ || !timer_) return Result::unavailable;
  xSemaphoreTake(mutex_, portMAX_DELAY);
  if (!enabled_) {
    xSemaphoreGive(mutex_);
    return Result::unavailable;
  }
  if (!state_.unlock(nowMs())) {
    xSemaphoreGive(mutex_);
    return Result::busy;
  }
  // A cutoff must be armed before energizing the relay. No network work under
  // this mutex, so the esp_timer task can always turn the relay off promptly.
  if (esp_timer_start_once(timer_, matter_config::pulseUs) != ESP_OK) {
    state_.lock();
    setRelay(false);
    xSemaphoreGive(mutex_);
    return Result::unavailable;
  }
  setRelay(true);
  xSemaphoreGive(mutex_);
  return Result::started;
}

void ReleaseOutput::stop() {
  if (!mutex_) return;
  xSemaphoreTake(mutex_, portMAX_DELAY);
  if (timer_) esp_timer_stop(timer_);
  state_.lock();
  setRelay(false);
  xSemaphoreGive(mutex_);
}

void ReleaseOutput::shutdown() {
  if (!mutex_) return;
  xSemaphoreTake(mutex_, portMAX_DELAY);
  enabled_ = false;
  if (timer_) esp_timer_stop(timer_);
  state_.lock();
  setRelay(false);
  xSemaphoreGive(mutex_);
}

bool ReleaseOutput::active() {
  if (!mutex_) return false;
  xSemaphoreTake(mutex_, portMAX_DELAY);
  const bool result = state_.active();
  xSemaphoreGive(mutex_);
  return result;
}

void ReleaseOutput::timerCallback(void* context) {
  static_cast<ReleaseOutput*>(context)->expire();
}

void ReleaseOutput::expire() {
  xSemaphoreTake(mutex_, portMAX_DELAY);
  // A previously dispatched callback must not stop a newer pulse.
  if (state_.expire(nowMs())) setRelay(false);
  xSemaphoreGive(mutex_);
}

void ReleaseOutput::updateIndicator() {
  const bool enabled = active();
  if (enabled == indicatorState_) return;
  indicatorState_ = enabled;
  // Keep the addressable LED driver out of the high-priority timer task.
  rgbLedWrite(config::indicatorPin, 0, enabled ? 32 : 0, 0);
}
