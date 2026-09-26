#pragma once
#include <WebServer.h>
#include "release_output.h"
#include "unlock_auth.h"

class LocalApi {
 public:
  LocalApi(ReleaseOutput& output, UnlockAuth& auth) : output_(output), auth_(auth) {}
  void begin();
  void poll();
  void printStatus();

 private:
  void headers();
  void json(int status, const String& body);
  WebServer server_{80};
  ReleaseOutput& output_;
  UnlockAuth& auth_;
  bool listening_ = false;
};
