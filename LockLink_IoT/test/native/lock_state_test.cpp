#include <cassert>
#include <cstdint>
#include <iostream>
#include "lock_state.h"

int main() {
  LockState state;
  assert(!state.active());
  assert(state.unlock(100));
  assert(state.active());
  assert(!state.unlock(500));  // Duplicate must not extend the release.
  assert(!state.expire(2099));
  assert(state.expire(2100));
  assert(!state.active());
  assert(!state.expire(3000));
  assert(state.unlock(4000));
  state.lock();
  assert(!state.active());
  assert(!state.expire(6000));
  assert(state.unlock(UINT32_MAX - 999));
  assert(!state.expire(999));
  assert(state.expire(1000));
  std::cout << "Lock state tests passed\n";
}
