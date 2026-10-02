#pragma once
#include <cstddef>
#include <cstdint>

namespace response_write {
// trySend must be nonblocking: positive is progress, zero retry, negative fatal.
template <class Send, class Clock, class Idle>
size_t write(const char* data, size_t size, uint32_t budgetMs,
             Send trySend, Clock now, Idle idle) {
  const uint32_t started = now();
  size_t written = 0;
  while (written < size && uint32_t(now() - started) < budgetMs) {
    const int count = trySend(data + written, size - written);
    if (count < 0 || size_t(count) > size - written) break;
    if (count == 0) idle();
    else written += size_t(count);
  }
  return written;
}
}
