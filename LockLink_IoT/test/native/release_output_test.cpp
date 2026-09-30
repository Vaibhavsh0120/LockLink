#include <cassert>
#include <iostream>
#include "release_output.h"

FakeTimer testTimer;
int64_t testTimeUs = 0;
bool failTimerStart = false;
int relayLevel = -1, indicatorLevel = -1;
bool relayOutputEnabled = false, indicatorOutputEnabled = false;

bool relayIs(int level) {
  return config::relayEnabled ? relayLevel == level :
                               relayLevel == -1 && !relayOutputEnabled;
}

int main() {
  ReleaseOutput output;
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(output.begin());
  assert(relayIs(LOW) && indicatorLevel == HIGH && indicatorOutputEnabled);
  assert(output.release() == ReleaseOutput::Result::started);
  assert(relayIs(HIGH) && indicatorLevel == LOW && testTimer.deadline == 1000000);
  testTimeUs = 500000;
  assert(output.release() == ReleaseOutput::Result::busy);
  assert(testTimer.deadline == 1000000);
  // Expiry callback cuts power with no Arduino loop or network processing.
  testTimeUs = 999000;
  testTimer.args.callback(testTimer.args.arg);
  assert(relayIs(HIGH) && indicatorLevel == LOW && output.active());
  testTimeUs = 1000000;
  testTimer.armed = false;
  testTimer.args.callback(testTimer.args.arg);
  assert(relayIs(LOW) && indicatorLevel == HIGH && !output.active());

  assert(output.release() == ReleaseOutput::Result::started);
  output.stop();
  assert(relayIs(LOW) && !testTimer.armed && !output.active());
  testTimeUs = 1250000;
  assert(output.release() == ReleaseOutput::Result::started);
  // A callback already dispatched for an old timer cannot end the new pulse.
  testTimer.args.callback(testTimer.args.arg);
  assert(relayIs(HIGH) && output.active());
  output.stop();

  failTimerStart = true;
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(relayIs(LOW) && indicatorLevel == HIGH && !output.active());
  failTimerStart = false;
  assert(output.release() == ReleaseOutput::Result::started);
  assert(indicatorLevel == LOW);
  output.stop();
  assert(indicatorLevel == HIGH);
  assert(output.release() == ReleaseOutput::Result::started);
  output.shutdown();
  assert(relayIs(LOW) && indicatorLevel == HIGH && !output.active());
  // Even a command already past its transport checks cannot race reset.
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(relayIs(LOW) && !testTimer.armed);
  std::cout << (config::relayEnabled ? "Relay" : "LED-only") << " output tests passed\n";
}
