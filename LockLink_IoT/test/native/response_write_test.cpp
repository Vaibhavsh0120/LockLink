#include "bounded_response_write.h"
#include <cassert>
#include <cstdint>
#include <cstdio>

int main() {
  const char body[] = "0123456789";
  uint32_t now = 0;
  unsigned calls = 0;
  auto clock = [&]() { return now; };
  auto idle = [&]() { ++now; };
  const auto stalled = [&](const char*, size_t) { ++calls; return 0; };
  assert(response_write::write(body, 10, 1000, stalled, clock, idle) == 0);
  assert(now == 1000 && calls == 1000);

  now = 0;
  calls = 0;
  const auto partial = [&](const char*, size_t) { return ++calls == 1 ? 3 : 0; };
  assert(response_write::write(body, 10, 1000, partial, clock, idle) == 3);
  assert(now == 1000);

  now = 0;
  calls = 0;
  const auto shortWrites = [&](const char* data, size_t length) {
    assert(data == body + calls * 2);
    ++calls;
    return int(length < 2 ? length : 2);
  };
  assert(response_write::write(body, 10, 1000, shortWrites, clock, idle) == 10);
  assert(calls == 5);

  calls = 0;
  const auto failed = [&](const char*, size_t) { ++calls; return -1; };
  assert(response_write::write(body, 10, 1000, failed, clock, idle) == 0);
  assert(calls == 1);

  now = UINT32_MAX - 500;
  const auto beforeWrap = now;
  assert(response_write::write(body, 10, 1000, stalled, clock, idle) == 0);
  assert(uint32_t(now - beforeWrap) == 1000);

  now = 0;
  const auto trickle = [&](const char*, size_t) { now += 200; return 1; };
  assert(response_write::write(body, 10, 1000, trickle, clock, idle) == 5);
  assert(now == 1000);
  assert(response_write::write(body, 0, 1000, stalled, clock, idle) == 0);
  puts("Bounded response write tests passed");
}
