#include "device_console.h"
#include <esp_random.h>

DeviceConsole console;

String jsonQuote(const String& text) {
  String result = "\"";
  for (size_t i = 0; i < text.length(); ++i) {
    const unsigned char c = text[i];
    if (c == '"' || c == '\\') { result += '\\'; result += char(c); }
    else if (c == '\n') result += "\\n";
    else if (c == '\r') result += "\\r";
    else if (c == '\t') result += "\\t";
    else if (c >= 32) result += char(c);
  }
  return result + '"';
}

void DeviceConsole::begin() {
  mutex_ = xSemaphoreCreateMutex();
  char id[17];
  snprintf(id, sizeof(id), "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
  boot_ = id;
}

size_t DeviceConsole::write(uint8_t c) { return write(&c, 1); }

size_t DeviceConsole::write(const uint8_t* data, size_t size) {
  if (!mutex_ || xSemaphoreTake(mutex_, pdMS_TO_TICKS(20)) != pdTRUE) return size;
  for (size_t i = 0; i < size; ++i) history_.write(char(data[i]));
  // An unplugged/full USB port must not stall the device's network loop.
  if (Serial && Serial.availableForWrite() >= int(size)) Serial.write(data, size);
  xSemaphoreGive(mutex_);
  return size;
}

String DeviceConsole::snapshot(uint32_t after, const String& boot) {
  if (!mutex_ || xSemaphoreTake(mutex_, pdMS_TO_TICKS(20)) != pdTRUE) return "";
  const bool sameBoot = boot == boot_;
  const bool gap = sameBoot && (after > history_.cursor() ||
      (history_.oldest() > 1 && after < history_.oldest() - 1));
  if (!sameBoot || after > history_.cursor()) after = 0;
  String result = String("\"version\":1,\"boot\":") + jsonQuote(boot_) +
      ",\"cursor\":" + String(history_.cursor()) + ",\"gap\":" + (gap ? "true" : "false") + ",\"lines\":[";
  bool first = true;
  for (uint32_t id = history_.oldest(); id <= history_.cursor(); ++id) {
    if (id <= after) continue;
    if (!first) result += ',';
    first = false;
    result += String("{\"id\":") + String(id) + ",\"text\":" + jsonQuote(history_.at(id).text) + '}';
  }
  xSemaphoreGive(mutex_);
  return result + ']';
}
