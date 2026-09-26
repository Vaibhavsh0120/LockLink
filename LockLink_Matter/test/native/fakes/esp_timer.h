#pragma once
#include <cstdint>
using esp_err_t = int;
constexpr esp_err_t ESP_OK = 0;
constexpr int ESP_TIMER_TASK = 0;
struct esp_timer_create_args_t {
  void (*callback)(void*) = nullptr;
  void* arg = nullptr;
  int dispatch_method = 0;
  const char* name = nullptr;
};
struct FakeTimer { esp_timer_create_args_t args; bool armed = false; uint64_t deadline = 0; };
using esp_timer_handle_t = FakeTimer*;
extern FakeTimer testTimer;
extern int64_t testTimeUs;
extern bool failTimerStart;
inline int64_t esp_timer_get_time() { return testTimeUs; }
inline esp_err_t esp_timer_create(const esp_timer_create_args_t* args, esp_timer_handle_t* result) {
  testTimer.args = *args;
  *result = &testTimer;
  return ESP_OK;
}
inline esp_err_t esp_timer_start_once(esp_timer_handle_t timer, uint64_t duration) {
  if (failTimerStart || timer->armed) return -1;
  timer->armed = true;
  timer->deadline = testTimeUs + duration;
  return ESP_OK;
}
inline esp_err_t esp_timer_stop(esp_timer_handle_t timer) {
  timer->armed = false;
  return ESP_OK;
}
