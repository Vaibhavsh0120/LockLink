#pragma once

#include <Arduino.h>

// A single-use challenge prevents a captured unlock request from being replayed.
class UnlockAuth {
 public:
  bool begin();
  bool ready() const { return ready_; }
  String issueChallenge(uint32_t nowMs);
  bool verify(const String& nonce, const String& signature, uint32_t nowMs,
              const String& action = "unlock");

 private:
  uint8_t key_[32] = {};
  String challenge_;
  uint32_t issuedAtMs_ = 0;
  bool ready_ = false;
};
