#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

namespace request_body {
template <typename Client, typename Clock, typename Idle>
char* read(Client& client, size_t length, size_t& received, uint32_t deadlineMs, Clock clock, Idle idle) {
  received = 0;
  if (!length || length > 128) return nullptr;
  char* body = static_cast<char*>(malloc(length + 1));
  if (!body) return nullptr;
  const uint32_t started = clock();
  while (received < length && uint32_t(clock() - started) < deadlineMs) {
    const size_t available = client.available();
    if (!available) {
      if (!client.connected()) break;
      idle();
      continue;
    }
    const size_t remaining = length - received;
    const size_t take = available < remaining ? available : remaining;
    const int count = client.read(reinterpret_cast<uint8_t*>(body) + received, take);
    if (count <= 0) break;
    received += size_t(count);
  }
  body[received] = '\0';
  return body;
}
}
