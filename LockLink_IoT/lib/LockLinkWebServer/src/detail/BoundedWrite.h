#pragma once
#include <Arduino.h>
#include <NetworkClient.h>
#include <cerrno>
#include <lwip/sockets.h>
#include "../../../../include/bounded_response_write.h"

namespace locklink_http {
inline size_t write(NetworkClient& client, const char* data, size_t size,
                    uint32_t budgetMs) {
  const int socket = client.fd();
  if (socket < 0) return 0;
  const size_t written = response_write::write(data, size, budgetMs,
      [socket](const char* chunk, size_t remaining) {
        const int count = send(socket, chunk, remaining, MSG_DONTWAIT);
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return 0;
        return count;
      }, []() { return uint32_t(millis()); }, []() { delay(1); });
  if (written != size) client.stop();
  return written;
}
}
