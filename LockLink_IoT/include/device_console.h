#pragma once
#include <Arduino.h>

class DeviceConsole : public Print {
 public:
  void begin() {}
  size_t write(uint8_t c) override;
  size_t write(const uint8_t* data, size_t size) override;
};
extern DeviceConsole console;
