#include <cassert>
#include "web_origin.h"

int main() {
  const char* origins[] = {"", "http://localhost:8765", "http://127.0.0.1:8765"};
  assert(web_origin::allowed("http://localhost:8765", origins, 3));
  assert(web_origin::allowed("http://127.0.0.1:8765", origins, 3));
  assert(!web_origin::allowed("", origins, 3));
  assert(!web_origin::allowed(nullptr, origins, 3));
  assert(!web_origin::allowed("null", origins, 3));
  assert(!web_origin::allowed("http://localhost:3000", origins, 3));
  assert(!web_origin::allowed("http://127.0.0.1:8765.evil.test", origins, 3));
  assert(!web_origin::allowed("https://elsewhere.test", origins, 3));
  return 0;
}
