#include "runtime_diagnostics.h"
#include <Arduino.h>
#include <driver/temperature_sensor.h>
#include <esp_system.h>
#include <esp_timer.h>
#include <esp_random.h>
#include <freertos/task.h>
#include <cmath>

namespace runtime_diagnostics {
namespace {
temperature_sensor_handle_t sensor = nullptr;
Snapshot current;
char boot[17] = {};
uint32_t lastLoop = 0, lastSample = 0;
bool hasLoopSample = false;
bool hasTemperatureSample = false;
}

bool begin() {
  snprintf(boot, sizeof(boot), "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
  current.resetReason = static_cast<uint32_t>(esp_reset_reason());
  const temperature_sensor_config_t config = TEMPERATURE_SENSOR_CONFIG_DEFAULT(10, 80);
  if (temperature_sensor_install(&config, &sensor) != ESP_OK) return false;
  if (temperature_sensor_enable(sensor) == ESP_OK) return true;
  temperature_sensor_uninstall(sensor);
  sensor = nullptr;
  return false;
}

void poll() {
  const uint32_t now = millis();
  if (hasLoopSample) {
    const uint32_t gap = now - lastLoop;
    if (gap > current.maxLoopGapMs) current.maxLoopGapMs = gap;
  }
  hasLoopSample = true;
  lastLoop = now;
  if (uint32_t(now - lastSample) < 1000) return;
  lastSample = now;
  current.loopStackMinimum = uxTaskGetStackHighWaterMark(nullptr);
  float value = 0;
  current.temperatureAvailable = sensor &&
      temperature_sensor_get_celsius(sensor, &value) == ESP_OK && std::isfinite(value);
  if (current.temperatureAvailable) {
    current.temperature = value;
    if (!hasTemperatureSample || value > current.maximumTemperature) current.maximumTemperature = value;
    hasTemperatureSample = true;
  } else {
    ++current.temperatureFailures;
  }
}

const char* bootId() { return boot; }

Snapshot snapshot() {
  Snapshot result = current;
  result.uptimeSeconds = static_cast<uint64_t>(esp_timer_get_time()) / 1000000;
  return result;
}
}
