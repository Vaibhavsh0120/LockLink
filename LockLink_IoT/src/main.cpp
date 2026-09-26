#include <Arduino.h>
#include "config.h"
#include "local_api.h"
#include "matter_release.h"
#include "release_output.h"
#include "unlock_auth.h"

ReleaseOutput output;
UnlockAuth auth;
LocalApi localApi(output, auth);
bool ready = false;

void setup() {
  Serial.begin(115200);
  if (!output.begin()) {
    Serial.println("Output initialization failed; door release disabled.");
    return;
  }
  auth.begin();
  const bool armed = !config::relayEnabled || auth.ready();
  if (!armed) Serial.println("Relay NOT armed: configure the app signing key.");
  localApi.begin();
  if (!matter_release::begin(output, armed)) {
    output.shutdown();
    Serial.println("Matter initialization failed; door release disabled.");
    return;
  }
  ready = true;
  matter_release::printStatus();
  Serial.printf("Output: %s; armed: %s\n",
      config::relayEnabled ? "relay" : "LED test", armed ? "yes" : "no");
  Serial.println("USB commands: STATUS, PAIR (setup code), RESET MATTER (erase pairings/Wi-Fi).");
}

void loop() {
  if (!ready) { delay(100); return; }
  matter_release::poll();
  output.updateIndicator();
  localApi.poll();
  // Bounded, nonblocking serial input; a partial line cannot stall the loop.
  static String command;
  while (Serial.available()) {
    const char c = Serial.read();
    if (c == '\n' || c == '\r') {
      command.trim();
      if (command == "PAIR") matter_release::printPairing();
      if (command == "STATUS") {
        matter_release::printStatus();
        localApi.printStatus();
        Serial.printf("Output: %s; armed: %s\n",
            config::relayEnabled ? "relay" : "LED test",
            (!config::relayEnabled || auth.ready()) ? "yes" : "no");
        Serial.println(output.active() ? "Release: active" : "Release: inactive");
      }
      if (command == "RESET MATTER") {
        ready = false;
        matter_release::resetPairing();
      }
      command = "";
    } else if (command.length() < 64) {
      command += c;
    } else {
      command = "";
    }
  }
  delay(2);
}
