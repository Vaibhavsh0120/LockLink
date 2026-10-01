#include <cassert>
#include <iostream>
#include <string>
#include "json_writer.h"

int main() {
  std::string output;
  size_t largestWrite = 0;
  JsonWriter writer([&](const char* data, size_t size) {
    if (size > largestWrite) largestWrite = size;
    output.append(data, size);
    return true;
  });
  assert(writer.raw("{\"text\":"));
  const char text[] = "quote\"\\\n\r\t\1 UTF-8: \xc3\xa9";
  assert(writer.quote(text, sizeof(text) - 1));
  assert(writer.raw(",\"cursor\":"));
  assert(writer.number(UINT32_MAX));
  assert(writer.raw("}"));
  assert(writer.finish());
  assert(output == "{\"text\":\"quote\\\"\\\\\\n\\r\\t\\u0001 UTF-8: \xc3\xa9\",\"cursor\":4294967295}");

  output.clear();
  const std::string large(6000, '\\');
  assert(writer.quote(large.data(), large.size()));
  assert(writer.finish());
  assert(output.size() == 12002 && largestWrite <= 256);
  size_t counted = 0;
  JsonWriter counter([&](const char*, size_t size) { counted += size; return true; });
  assert(counter.quote(large.data(), large.size()) && counter.finish());
  assert(counted == output.size()); // Content-Length agrees with streamed JSON.

  int calls = 0;
  JsonWriter failing([&](const char*, size_t) { ++calls; return false; });
  assert(!failing.raw(large.data(), large.size()));
  assert(!failing.finish() && calls == 1); // A failed sink never reports success.
  std::cout << "JSON writer tests passed\n";
}
