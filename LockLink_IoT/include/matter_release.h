#pragma once
#include "release_output.h"

namespace matter_release {
bool begin(ReleaseOutput& output, bool armed);
void poll();
void printPairing();
void printStatus();
void resetPairing();
bool commissioned();
String identity();
String preparePairing(String& message, String& qrPayload);
String prepareAdditionalPairing(String& message, String& qrPayload);
bool closePairing(String& message);
bool manageHome(const String& id, const String& hexLabel, bool remove, String& message);
struct HomesSnapshot {
  bool commissioned = false;
  bool windowOpen = false;
  bool additional = false;
  String json = "[]";
  String description;
  String windowId;
  unsigned capacity = 0;
};
HomesSnapshot homesSnapshot();
}
