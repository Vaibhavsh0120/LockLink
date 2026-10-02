# LockLink App Reliability Implementation Plan

Goal: keep authenticated app opening responsive on the ESP32-C3, including four
foreground phones, without depending on Matter/BLE memory or changing the output
polarity, one-second timer, app key, or saved pairing data.

1. Reproduce transport stalls and collect heap/reset/network/temperature evidence.
2. Bound HTTP parsing and body allocations in a project-local copy of the pinned
   Arduino WebServer. Test fragmented legitimate bodies and absolute deadlines.
3. User's later scope supersedes the two-profile plan: remove Matter and app
   Terminal entirely in v2.2.0. Keep `esp32-c3-supermini` as the sole environment.
   App-only has one ESP-IDF Wi-Fi owner with bounded reconnect
   backoff and a DHCP recovery deadline. Never erase NVS on boot failure.
4. Preserve status/challenge/unlock for installed apps; delete network Terminal,
   history, smart-home screens, QR dependencies, and platform handoffs. Keep tiny
   USB-only read-only health reporting and explicit reconnect diagnostics.
5. Add loop watchdog and diagnostics. Keep release cutoff independent of HTTP.
6. Build/verify the sole environment and flash only the application partition on the
   isolated board. Test four independent clients, bursts, partial/oversized
   requests, fragmented authenticated requests, reconnects, and USB flooding.
7. User caps test sessions at 15 minutes and confirms Android widgets and the
   iOS app in LiveContainer already work. Leave those paths unchanged. Test
   status/challenge/unlock bursts as well as foreground load; report failed
   trials honestly. Installed charger/cable/circuit verification remains a
   separate hardware boundary. Never automatically retry an uncertain release.
