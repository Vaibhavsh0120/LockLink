#include "bounded_request_body.h"
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>

struct Peer {
  std::string data;
  size_t offset = 0, fragment = 2048;
  uint32_t now = 0, readDelay = 0;
  bool connected() { return true; }
  size_t available() { return data.size() - offset; }
  int read(uint8_t* buffer, size_t length) {
    const size_t count = std::min(length, std::min(fragment, available()));
    memcpy(buffer, data.data() + offset, count);
    offset += count;
    now += readDelay;
    return count;
  }
};

int main() {
  const auto read = [](Peer& peer, size_t length, size_t& received) {
    return request_body::read(peer, length, received, 1000,
        [&]() { return peer.now; }, [&]() { ++peer.now; });
  };
  Peer split{"STATUS", 0, 1};
  size_t received = 0;
  char* body = read(split, 6, received);
  assert(body && received == 6 && std::strcmp(body, "STATUS") == 0);
  free(body);
  Peer extra{"STATUSNEXT"};
  body = read(extra, 6, received);
  assert(body && received == 6 && extra.offset == 6 && std::strcmp(body, "STATUS") == 0);
  free(body);
  Peer trickle{"STATUS", 0, 1, 0, 300};
  body = read(trickle, 6, received);
  assert(body && received == 4 && trickle.offset == 4 && trickle.now == 1200);
  free(body);
  Peer stalled{""};
  body = read(stalled, 6, received);
  assert(body && received == 0 && stalled.now == 1000);
  free(body);
  Peer oversized{std::string(129, 'x')};
  assert(read(oversized, 129, received) == nullptr && received == 0 && oversized.offset == 0);
  assert(read(oversized, 0, received) == nullptr && received == 0);
  Peer maximum{std::string(128, 'x'), 0, 1, UINT32_MAX - 10};
  body = read(maximum, 128, received);
  assert(body && received == 128 && body[128] == '\0');
  free(body);
  Peer wrap{"", 0, 1, UINT32_MAX - 10};
  body = read(wrap, 6, received);
  assert(body && received == 0 && wrap.now == 989);
  free(body);
  std::cout << "Bounded request body tests passed\n";
}
