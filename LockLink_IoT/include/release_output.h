#pragma once
#include <Arduino.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include "lock_state.h"

class ReleaseOutput {
 public:
  enum class Result { started, busy, unavailable };
  bool begin();
  Result release();
  void stop();
  void shutdown();
  bool active();

 private:
  static void timerCallback(void* context);
  void expire();
  void setRelay(bool enabled);
  SemaphoreHandle_t mutex_ = nullptr;
  esp_timer_handle_t timer_ = nullptr;
  LockState state_;
  bool enabled_ = false;
};
