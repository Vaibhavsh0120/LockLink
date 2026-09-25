#include "unlock_auth.h"

#include <esp_random.h>
#include <mbedtls/md.h>

#include "config.h"

namespace {
int hexNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool decodeHex(const String& value, uint8_t* out, size_t bytes) {
  if (value.length() != bytes * 2) return false;
  for (size_t i = 0; i < bytes; ++i) {
    const int hi = hexNibble(value[i * 2]);
    const int lo = hexNibble(value[i * 2 + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = static_cast<uint8_t>((hi << 4) | lo);
  }
  return true;
}

String encodeHex(const uint8_t* data, size_t bytes) {
  static const char digits[] = "0123456789abcdef";
  String result;
  result.reserve(bytes * 2);
  for (size_t i = 0; i < bytes; ++i) {
    result += digits[data[i] >> 4];
    result += digits[data[i] & 0x0f];
  }
  return result;
}
}  // namespace

bool UnlockAuth::begin() {
  ready_ = config::relayEnabled &&
      decodeHex(String(config::unlockKeyHex), key_, sizeof(key_));
  return ready_;
}

String UnlockAuth::issueChallenge(uint32_t nowMs) {
  if (!ready_) return "";
  uint8_t randomBytes[16];
  esp_fill_random(randomBytes, sizeof(randomBytes));
  challenge_ = encodeHex(randomBytes, sizeof(randomBytes));
  issuedAtMs_ = nowMs;
  return challenge_;
}

bool UnlockAuth::verify(
    const String& nonce, const String& signature, uint32_t nowMs) {
  if (!ready_ || challenge_.isEmpty() || nonce != challenge_ ||
      uint32_t(nowMs - issuedAtMs_) > 10000) {
    challenge_ = "";
    return false;
  }
  challenge_ = "";  // Consume the nonce before checking the signature.
  uint8_t submitted[32];
  if (!decodeHex(signature, submitted, sizeof(submitted))) return false;
  const String message = String("unlock:") + nonce;
  uint8_t expected[32];
  const mbedtls_md_info_t* sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (sha256 == nullptr ||
      mbedtls_md_hmac(sha256, key_, sizeof(key_),
          reinterpret_cast<const unsigned char*>(message.c_str()),
          message.length(), expected) != 0) {
    return false;
  }
  uint8_t difference = 0;
  for (size_t i = 0; i < sizeof(expected); ++i) {
    difference |= expected[i] ^ submitted[i];
  }
  return difference == 0;
}
