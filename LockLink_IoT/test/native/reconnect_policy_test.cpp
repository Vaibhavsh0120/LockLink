#include <cassert>
#include <iostream>
#include "reconnect_policy.h"

int main() {
  ReconnectPolicy retry;
  assert(!retry.due(0, false));
  assert(!retry.due(4999, false));
  assert(retry.due(5000, false));
  assert(!retry.due(5001, false));
  assert(!retry.due(14999, false));
  assert(retry.due(15000, false));
  assert(!retry.due(34999, false));
  assert(retry.due(35000, false));
  assert(retry.due(65000, false));
  assert(retry.due(95000, false));
  assert(!retry.due(96000, true)); // A ready link resets the delay.
  assert(!retry.due(100999, false));
  assert(retry.due(101000, false));
  assert(!retry.due(0xfffffff0, true));
  assert(!retry.due(0x1377, false));
  assert(retry.due(0x1378, false)); // Unsigned clock wrap.
  std::cout << "Reconnect policy tests passed\n";
}
