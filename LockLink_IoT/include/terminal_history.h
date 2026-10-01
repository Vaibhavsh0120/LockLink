#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

// Fixed memory, whole lines, monotonic cursor. Caller provides synchronization.
class TerminalHistory {
 public:
  // Keep the C3's fixed history below 3 KB, leaving RAM for Matter and Wi-Fi.
  static constexpr size_t capacity = 16;
  static constexpr size_t lineSize = 160;
  struct Line { uint32_t id = 0; char text[lineSize + 1] = {}; };
  void write(char c) {
    if (c == '\r') return;
    if (c == '\n') {
      if (length_ == 0) return;
      auto& line = lines_[cursor_ % capacity];
      line.id = ++cursor_;
      memcpy(line.text, pending_, length_);
      line.text[length_] = '\0';
      length_ = 0;
    } else if (length_ < lineSize && static_cast<unsigned char>(c) >= 32) {
      pending_[length_++] = c;
    }
  }
  uint32_t cursor() const { return cursor_; }
  uint32_t oldest() const { return cursor_ >= capacity ? cursor_ - capacity + 1 : 1; }
  const Line& at(uint32_t id) const { return lines_[(id - 1) % capacity]; }
 private:
  Line lines_[capacity];
  char pending_[lineSize] = {};
  size_t length_ = 0;
  uint32_t cursor_ = 0;
};
static_assert(sizeof(TerminalHistory) <= 3072, "Terminal history exceeds C3 RAM budget");
