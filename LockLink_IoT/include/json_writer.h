#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

// JSON serialization with a fixed stack buffer. A sink returns false on write
// failure. Counting and sending use the same encoder, without a full JSON copy.
template <typename Sink>
class JsonWriter {
 public:
  explicit JsonWriter(Sink sink) : sink_(sink) {}
  bool raw(const char* text) { return raw(text, strlen(text)); }
  bool raw(const char* text, size_t size) {
    while (ok_ && size) {
      const size_t room = sizeof(buffer_) - used_;
      const size_t take = size < room ? size : room;
      memcpy(buffer_ + used_, text, take);
      used_ += take;
      text += take;
      size -= take;
      if (used_ == sizeof(buffer_)) flush();
    }
    return ok_;
  }
  bool number(uint32_t value) {
    char digits[11];
    snprintf(digits, sizeof(digits), "%lu", static_cast<unsigned long>(value));
    return raw(digits);
  }
  bool quote(const char* text, size_t size) {
    raw("\"");
    for (size_t i = 0; ok_ && i < size; ++i) {
      const unsigned char c = text[i];
      if (c == '"') raw("\\\"");
      else if (c == '\\') raw("\\\\");
      else if (c == '\n') raw("\\n");
      else if (c == '\r') raw("\\r");
      else if (c == '\t') raw("\\t");
      else if (c < 32) {
        const char hex[] = "0123456789abcdef";
        const char escaped[] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
        raw(escaped, sizeof(escaped));
      } else raw(text + i, 1);
    }
    return raw("\"");
  }
  bool finish() { flush(); return ok_; }
 private:
  void flush() {
    if (ok_ && used_) ok_ = sink_(buffer_, used_);
    used_ = 0;
  }
  Sink sink_;
  char buffer_[256];
  size_t used_ = 0;
  bool ok_ = true;
};
