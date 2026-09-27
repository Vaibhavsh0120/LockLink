#pragma once
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include "terminal_history.h"

String jsonQuote(const String& text);

class DeviceConsole : public Print {
 public:
  void begin();
  size_t write(uint8_t c) override;
  size_t write(const uint8_t* data, size_t size) override;
  String snapshot(uint32_t after, const String& boot);
 private:
  SemaphoreHandle_t mutex_ = nullptr;
  TerminalHistory history_;
  String boot_;
};
extern DeviceConsole console;
