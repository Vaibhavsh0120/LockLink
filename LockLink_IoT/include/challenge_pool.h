#pragma once
#include <cstdint>
#include <cstring>

// Outstanding nonces belong to requests, so one phone cannot replace another's.
// A full pool rejects new requests rather than evicting an unexpired nonce.
class ChallengePool {
 public:
  bool add(const uint8_t* nonce, uint32_t now) {
    expire(now);
    for (const auto& slot : slots_) {
      if (slot.live && memcmp(slot.nonce, nonce, 16) == 0) return false;
    }
    for (auto& slot : slots_) {
      if (!slot.live) {
        memcpy(slot.nonce, nonce, 16);
        slot.issued = now;
        slot.live = true;
        return true;
      }
    }
    return false;
  }
  bool take(const uint8_t* nonce, uint32_t now) {
    expire(now);
    for (auto& slot : slots_) {
      if (slot.live && memcmp(slot.nonce, nonce, 16) == 0) {
        slot.live = false;
        return true;
      }
    }
    return false;
  }
 private:
  void expire(uint32_t now) {
    for (auto& slot : slots_) {
      if (slot.live && uint32_t(now - slot.issued) > 10000) slot.live = false;
    }
  }
  struct Slot { uint8_t nonce[16] = {}; uint32_t issued = 0; bool live = false; };
  Slot slots_[8];
};
