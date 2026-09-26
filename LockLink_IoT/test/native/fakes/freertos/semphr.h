#pragma once
#include <mutex>
using SemaphoreHandle_t = std::mutex*;
inline SemaphoreHandle_t xSemaphoreCreateMutex() { static std::mutex mutex; return &mutex; }
inline void xSemaphoreTake(SemaphoreHandle_t mutex, unsigned) { mutex->lock(); }
inline void xSemaphoreGive(SemaphoreHandle_t mutex) { mutex->unlock(); }
