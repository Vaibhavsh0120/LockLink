# C3 Memory Recovery Implementation Plan

> Execute inline under the user's instruction to continue and fix the issue. Use test-driven-development and verification-before-completion. No approval handoff is needed for the already authorized local repair and disconnected-board testing.

**Goal:** Increase the ESP32-C3's network memory margin and verify repeated local status access stays responsive.

**Architecture:** Reduce fixed terminal history from 64 to 16 lines while preserving cursor/gap semantics. Add allocation diagnostics without allocating in the failure callback. Bound driver RX/TX buffers before Matter starts Wi-Fi, preserve BLE commissioning and connection ownership, and stream Terminal JSON through a fixed buffer. Flash only the application partition to preserve NVS.

**Tech stack:** ESP32-C3 Super Mini, Arduino 3.3.12, ESP-IDF, PlatformIO, native C++ tests, Flutter.

**Spec:** `LockLink_Docs/CONNECTION_DIAGNOSIS_2026-10-01.md` and the user's instruction to fix the memory issue.

## Constraints

- Preserve the existing uncommitted app and diagnostic changes.
- Relay remains physically disconnected. Do not send release or pairing-changing commands.
- Preserve NVS, saved Wi-Fi, keys and Matter pairing. Do not flash a factory image or erase storage.
- Do not install a second Wi-Fi/reconnect manager or automatically replay commands.

## Review focus

- Terminal history wraps cleanly and retains monotonically increasing IDs.
- Memory failure callbacks must avoid heap allocation and blocking output.
- Frequent status reads, slow/idle clients and idle gaps must not leave networking unusable.
- Status failures must keep app commands disabled and recover without a restart.

## Task 1: Recover static RAM and expose memory pressure

- [x] Add a failing regression to `test/native/terminal_history_test.cpp`: history occupies at most 3 KB, retains the newest 16 complete lines and preserves 160-character truncation.
- [x] Reduce `include/terminal_history.h` capacity to 16; run `python LockLink_IoT/tools/test_native.py`.
- [x] Add `memory_diagnostics.h/.cpp`, register the allocation failure counter at startup, and report free/minimum/largest heap and failure count through USB/authenticated `STATUS`.
- [x] Build `esp32-c3-supermini`; confirm static RAM decreases and firmware fits.

## Task 2: Verify on the actual board and close the recovery path

- [x] Preserve the previous application image outside the checkout and confirm the application partition offset.
- [x] Flash only the application partition on COM7, without erasing storage.
- [x] Run repeated status reads, challenge reads, idle-client recovery and idle gaps while sampling USB memory/uptime; send no release command.
- [x] If the outage persists, use the allocation diagnostics to choose the next focused correction; do not conceal it with automatic reboots.
- [x] Reuse the existing Flutter state-sync tests and verify the complete relevant native suites and final diff.
- [x] Have one fresh-context reviewer check the final firmware changes; update diagnosis and recovery documentation with measured results and remaining limits.

## Decisions and execution record

- The user explicitly instructed autonomous continuation, so implementation proceeds in the current checkout.
- Initial reset restored network access; old firmware's later free heap settled around 11.6 KB after a small run. Earlier sustained outage reached 6–7 KB.
- The retained-history trade-off is 16 recent lines rather than 64; per-line size and cursor/gap semantics remain intact.
- The regression failed against the old footprint, then all six native test executables passed after the reduction. PlatformIO built successfully (static RAM 89,976 bytes; flash 1,838,607 bytes).
- Link maps show `console` reduced from 10,948 to 2,884 bytes, a saving of 8,064 bytes. Allocation tracking adds a small fixed counter.
- The actual device partition table was read and checked: app0 starts at `0x20000`; NVS starts at `0x10000`. Flashing at the common default `0x10000` would overwrite NVS and is explicitly excluded.
- The user confirmed older logs are unnecessary and latest logs are the priority. Source inspection confirms Home and Terminal already pause polling outside their active view/lifecycle.
- A full 4 MB device backup was read before programming. Application-only flashes at `0x20000` were hash-verified; NVS was not erased.
- History reduction alone was insufficient: a 325.8-second run completed 373/376 requests but recorded 14 failed allocations of 2,312 bytes and a minimum heap of 244 bytes. Terminal traffic increased the failures. The user confirmed phone cold launch and foreground recovery now work automatically.
- ArduinoMatter already uses static RX 4 / dynamic RX 8 / dynamic TX 8 / RX BA 6, rather than the much larger SDK defaults. The second correction explicitly initializes ESP-IDF driver allocation limits before `Matter.begin()`: static RX 2 / dynamic RX and TX 4 / RX BA 4, AMPDU RX off. Disabling AMPDU RX follows Espressif's recommendation below six static RX buffers. Matter inherits these limits without another connection manager; BLE commissioning remains available.
- The second image completed all 376 HTTP responses with zero allocation failures, steady free heap 23,496 bytes and lifetime minimum 1,772 bytes. Three status replies were valid HTTP 200 while the output was active (the initial benchmark incorrectly required locked). The harness now treats both documented states as valid and records them.
- The reviewer found an unchecked whole-response allocation in Terminal. The final correction uses a fixed 256-byte JSON streaming buffer with identical counting/sending serialization; history serialization reserves once and checks every write before executing a command. A focused regression covers escaping, UTF-8, maximum cursor, large output, Content-Length counting and sink failure. All seven native suites passed.
- All 74 Flutter tests and Flutter analysis passed; no further app source changes were needed in this stage.
- Final short-write handling checks the actual client byte count, propagates encoder failure and closes a failed response. Reviewer confirmed the correction and found no remaining concrete issue.
- Final build passed (static RAM 89,976 bytes, flash 1,841,879 bytes); application-only COM7 flash was hash-verified. The final 316.6-second comparison completed 376/376 valid requests, including repeated authenticated Terminal JSON responses, with zero timeouts/allocation failures and monotonic uptime. Final free heap was 23,284 bytes, largest block 12,276 bytes, lifetime minimum 4,964 bytes. Previous stages and final results were retained outside the checkout.
