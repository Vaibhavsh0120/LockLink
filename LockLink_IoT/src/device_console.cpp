#include "device_console.h"

DeviceConsole console;

size_t DeviceConsole::write(uint8_t c) { return write(&c, 1); }

size_t DeviceConsole::write(const uint8_t* data, size_t size) {
  // No retained logs. An unplugged/full USB port must not stall networking.
  if (Serial && Serial.availableForWrite() >= int(size)) Serial.write(data, size);
  return size;
}
