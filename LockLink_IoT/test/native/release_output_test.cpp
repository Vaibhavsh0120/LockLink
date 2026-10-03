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
  constexpr int IDLE = HIGH, PULSE = LOW;
  ReleaseOutput output;
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(output.begin());
  assert(relayIs(IDLE) && indicatorLevel == HIGH && indicatorOutputEnabled);
  assert(output.release() == ReleaseOutput::Result::started);
  assert(relayIs(PULSE) && indicatorLevel == LOW && testTimer.deadline == 500000);
  testTimeUs = 250000;
  assert(output.release() == ReleaseOutput::Result::busy);
  assert(testTimer.deadline == 500000);
  // Expiry restores idle HIGH without Arduino loop or network processing.
  testTimeUs = 499000;
  testTimer.args.callback(testTimer.args.arg);
  assert(relayIs(PULSE) && indicatorLevel == LOW && output.active());
  testTimeUs = 500000;
  testTimer.armed = false;
  testTimer.args.callback(testTimer.args.arg);
  assert(relayIs(IDLE) && indicatorLevel == HIGH && !output.active());

  assert(output.release() == ReleaseOutput::Result::started);
  output.stop();
  assert(relayIs(IDLE) && !testTimer.armed && !output.active());
  testTimeUs = 1250000;
  assert(output.release() == ReleaseOutput::Result::started);
  // A callback already dispatched for an old timer cannot end the new pulse.
  testTimer.args.callback(testTimer.args.arg);
  assert(relayIs(PULSE) && output.active());
  output.stop();

  failTimerStart = true;
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(relayIs(IDLE) && indicatorLevel == HIGH && !output.active());
  failTimerStart = false;
  assert(output.release() == ReleaseOutput::Result::started);
  assert(indicatorLevel == LOW);
  output.stop();
  assert(indicatorLevel == HIGH);
  assert(output.release() == ReleaseOutput::Result::started);
  output.shutdown();
  assert(relayIs(IDLE) && indicatorLevel == HIGH && !output.active());
  // Even a command already past its transport checks cannot race reset.
  assert(output.release() == ReleaseOutput::Result::unavailable);
  assert(relayIs(IDLE) && !testTimer.armed);
  std::cout << (config::relayEnabled ? "Relay" : "LED-only") << " output tests passed\n";
}
