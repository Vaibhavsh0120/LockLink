#pragma once
#include "release_output.h"

namespace matter_release {
bool begin(ReleaseOutput& output, bool armed);
void poll();
void printPairing();
void printStatus();
void resetPairing();
}
