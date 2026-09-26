#include <cassert>
#include <iostream>
#include "release_output.h"

FakeTimer testTimer;
int64_t testTimeUs = 0;
bool failTimerStart = false;
int relayLevel = -1, indicatorGreen = -1;

int main() {
  ReleaseOutput output;
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(output.begin());
  assert(relayLevel == LOW && indicatorGreen == 0);
  assert(output.release() == ReleaseOutput::Result::started);
  assert(relayLevel == HIGH && testTimer.deadline == 2000000);
  testTimeUs = 1000000;
  assert(output.release() == ReleaseOutput::Result::busy);
  assert(testTimer.deadline == 2000000);
  // Expiry callback cuts power with no Arduino loop or network processing.
  testTimeUs = 2000000;
  testTimer.armed = false;
  testTimer.args.callback(testTimer.args.arg);
  assert(relayLevel == LOW && !output.active());

  assert(output.release() == ReleaseOutput::Result::started);
  output.stop();
  assert(relayLevel == LOW && !testTimer.armed && !output.active());
  testTimeUs = 2500000;
  assert(output.release() == ReleaseOutput::Result::started);
  // A callback already dispatched for an old timer cannot end the new pulse.
  testTimer.args.callback(testTimer.args.arg);
  assert(relayLevel == HIGH && output.active());
  output.stop();

  failTimerStart = true;
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(relayLevel == LOW && !output.active());
  failTimerStart = false;
  assert(output.release() == ReleaseOutput::Result::started);
  output.updateIndicator();
  assert(indicatorGreen == 32);
  output.stop();
  output.updateIndicator();
  assert(indicatorGreen == 0);
  assert(output.release() == ReleaseOutput::Result::started);
  output.shutdown();
  assert(relayLevel == LOW && !output.active());
  // Even a command already past its transport checks cannot race reset.
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(relayLevel == LOW && !testTimer.armed);
  std::cout << "Release output tests passed\n";
}
