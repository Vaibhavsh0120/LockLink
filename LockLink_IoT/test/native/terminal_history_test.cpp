#include "terminal_history.h"
#include <cassert>
#include <cstring>
#include <iostream>

int main() {
  TerminalHistory history;
  for (int i = 0; i < 200; ++i) history.write('x');
  history.write('\r');
  history.write('\n');
  assert(history.cursor() == 1);
  assert(strlen(history.at(1).text) == 160);
  history.write('\n');
  assert(history.cursor() == 1);
  for (int i = 0; i < 80; ++i) { history.write('a'); history.write('\n'); }
  assert(history.cursor() == 81);
  assert(history.oldest() == 18);
  for (uint32_t i = history.oldest(); i <= history.cursor(); ++i) {
    assert(history.at(i).id == i);
    assert(strcmp(history.at(i).text, "a") == 0);
  }
  std::cout << "Terminal history tests passed\n";
}
