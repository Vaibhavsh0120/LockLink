#include <Arduino.h>
#include "config.h"
#include "local_api.h"
#include "matter_release.h"
#include "release_output.h"
#include "unlock_auth.h"
#include "device_console.h"
#include "terminal_commands.h"

ReleaseOutput output;
UnlockAuth auth;
LocalApi localApi(output, auth);
bool ready = false;

void setup() {
  const bool outputReady = output.begin();
  Serial.begin(115200);
  console.begin();
  if (!outputReady) {
    console.println("Output failed. Release disabled.");
    return;
  }
  auth.begin();
  const bool armed = !config::relayEnabled || auth.ready();
  if (!armed) console.println("Relay not armed. Configure app key.");
  localApi.begin();
  if (!matter_release::begin(output, armed)) {
    output.shutdown();
    console.println("Matter failed. Release disabled.");
    return;
  }
  ready = true;
  matter_release::printStatus();
  console.printf("Output: %s; armed: %s\n",
      config::relayEnabled ? "relay" : "LED test", armed ? "yes" : "no");
  console.println("Ready. Type HELP for commands.");
}

void loop() {
  if (!ready) { delay(100); return; }
  matter_release::poll();
  localApi.poll();
  static bool lastRelease = false;
  const bool releasing = output.active();
  if (releasing != lastRelease) {
    lastRelease = releasing;
    console.println(releasing ? "Release: active" : "Release: inactive");
  }
  static uint32_t lastMatterCheck = 0;
  static bool lastPaired = false;
  if (uint32_t(millis() - lastMatterCheck) >= 1000) {
    lastMatterCheck = millis();
    const bool paired = matter_release::commissioned();
    if (paired != lastPaired) {
      lastPaired = paired;
      console.println(paired ? "Matter: paired" : "Matter: not paired");
    }
  }
  // Bounded, nonblocking serial input; a partial line cannot stall the loop.
  static String command;
  static bool overflow = false;
  while (Serial.available()) {
    const char c = Serial.read();
    if (c == '\n' || c == '\r') {
      command.trim();
      command.toUpperCase();
      if (overflow) {
        Serial.println("Command too long. Maximum 128 characters.");
      } else if (command == "RESET MATTER") {
        ready = false;
        matter_release::resetPairing();
      } else if (!command.isEmpty()) {
        // Private responses, including Matter codes, are not added to history.
        Serial.println(terminalCommand(command, output, auth).output);
      }
      command = "";
      overflow = false;
    } else if (!overflow && command.length() < 128) {
      command += c;
    } else {
      overflow = true;
    }
  }
  delay(2);
}
