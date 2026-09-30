#pragma once
#include <Arduino.h>
#include "release_output.h"
#include "unlock_auth.h"

struct TerminalReply {
  bool ok = true;
  bool commissioned = false;
  String output;
  String pairingCode;
  String pairingQrPayload;
  String homesJson = "[]";
  unsigned fabricCapacity = 0;
  bool pairingWindowOpen = false;
  bool additionalPairing = false;
  String pairingWindowId;
};
TerminalReply terminalCommand(String command, ReleaseOutput& output, UnlockAuth& auth);
