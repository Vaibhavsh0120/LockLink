#include "challenge_pool.h"
#include <cassert>
#include <cstdio>

int main() {
  ChallengePool pool;
  uint8_t first[16] = {1}, second[16] = {2}, unknown[16] = {3};
  assert(pool.add(first, 100));
  assert(pool.add(second, 101));
  assert(!pool.take(unknown, 102));
  assert(pool.take(first, 103));
  assert(!pool.take(first, 104));
  assert(pool.take(second, 105));
  assert(pool.add(first, UINT32_MAX - 100));
  assert(pool.take(first, 50));  // millis wrap, still within ten seconds
  assert(pool.add(first, 0));
  assert(!pool.take(first, 10001));
  for (uint8_t i = 1; i <= 8; ++i) {
    uint8_t nonce[16] = {i};
    assert(pool.add(nonce, 20000));
  }
  uint8_t ninth[16] = {9};
  assert(!pool.add(ninth, 20001));
  assert(pool.take(first, 20002));  // capacity failure did not evict it
  assert(pool.add(ninth, 20003));
  assert(pool.add(first, 30004));  // expired slots become reusable
  puts("Challenge pool tests passed.");
}
