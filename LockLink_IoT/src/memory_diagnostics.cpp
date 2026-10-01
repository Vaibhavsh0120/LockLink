#include "memory_diagnostics.h"
#include <esp_heap_caps.h>
#include <freertos/FreeRTOS.h>

namespace memory_diagnostics {
namespace {
portMUX_TYPE counterMutex = portMUX_INITIALIZER_UNLOCKED;
uint32_t allocationFailures = 0;
size_t lastFailedBytes = 0;

// This runs in the allocating task. Never allocate, format strings or print
// here: the heap may be exhausted and the callback can run concurrently.
void allocationFailed(size_t bytes, uint32_t, const char*) {
  portENTER_CRITICAL(&counterMutex);
  ++allocationFailures;
  lastFailedBytes = bytes;
  portEXIT_CRITICAL(&counterMutex);
}
}

bool begin() {
  return heap_caps_register_failed_alloc_callback(allocationFailed) == ESP_OK;
}

Snapshot snapshot() {
  multi_heap_info_t heap = {};
  heap_caps_get_info(&heap, MALLOC_CAP_8BIT);
  Snapshot result;
  result.free = heap.total_free_bytes;
  result.minimum = heap.minimum_free_bytes;
  result.largest = heap.largest_free_block;
  portENTER_CRITICAL(&counterMutex);
  result.allocationFailures = allocationFailures;
  result.lastFailedBytes = lastFailedBytes;
  portEXIT_CRITICAL(&counterMutex);
  return result;
}
}
