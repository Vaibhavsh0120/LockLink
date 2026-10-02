#pragma once
#include <stddef.h>
#include <string.h>

namespace web_origin {
inline bool allowed(const char* origin, const char* const* origins, size_t count) {
  if (!origin || !origin[0] || strcmp(origin, "null") == 0) return false;
  for (size_t index = 0; index < count; ++index) {
    if (origins[index] && origins[index][0] && strcmp(origin, origins[index]) == 0) return true;
  }
  return false;
}
}
