# Reliability investigation: 2026-10-02

## Result

**The intermittent offline problem is reproduced, but not fully solved.**
Version 2.2.0 removes Matter and the network Terminal, substantially increases
heap headroom, bounds HTTP stalls, and recovers deliberate Wi-Fi disconnects.
However, this physical board still loses packets in some app-only trials,
including one-client traffic. Do not certify permanent installation from these
bench results or claim that four installed apps are the sole cause.

The board was isolated, on wood, powered by laptop USB, with no relay attached.
The user confirms Android widgets and the iOS app in LiveContainer already work;
those control paths were not redesigned. Their installation does not create
continuous device traffic: Android widgets issue requests only when tapped.
Each relay tap uses status, a fresh challenge, then a signed unlock request.
The iOS Flutter app polls only while its Home screen is foregrounded.

## Measurements

All command tests below used the physically disconnected output. A timed-out
command sequence stops further pulses; uncertain unlocks are never replayed.
Status reports commanded output state, not physical door position or pin timing.

| Trial | Result |
| --- | --- |
| Original installed firmware, 125.6 s | 177 valid status replies; two deliberately incomplete-peer failures; an idle peer delayed a real request 5,078 ms. Minimum heap 3,164 bytes. |
| App-only, Terminal still present, 111.8 s | 454 replies; four failures; two verified output cycles; minimum heap 178,236 bytes; no allocation failure/reset. |
| v2.2.0, 6 static / 16 dynamic buffers, RX aggregation on, 144.1 s | 191 replies; 17 failures; minimum heap 155,800 bytes; no allocation failure/reset. Rejected. |
| v2.2.0, 6/16, RX aggregation off, warm 108.3 s | 250 replies; 18 failures; one verified cycle; second sequence timed out and later pulses were aborted. Rejected. |
| v2.2.0, 6/16, 8.5 dBm TX maximum, 178.3 s | 123 replies; 68 failures; minimum heap 144,720 bytes; no allocation failure/reset. Lower TX power did not help this trial. Rejected. |
| v2.2.0, retained 2/4 profile, 1,500 ms idle bound, 107.2 s | Four clients; 469 replies; zero failures; two verified cycles; minimum heap 182,984 bytes; one boot, no allocation failure/disconnect. Short pass only. |
| Same retained profile, one client, 96.1 s | 121 replies; zero failures; median 78 ms, p95 157 ms, maximum 2,672 ms. Short pass only. |
| Retained profile, missing-LF deadline fix, longer four-client trial | At the 360 s progress checkpoint: 1,607 replies, 55 failures, eight verified cycles. Later pulses aborted after a timeout. Run interrupted after reproducing failure; no completed-soak claim. |
| Retained 2/4 profile with TX aggregation disabled | One client: at the 240 s checkpoint, 238 replies and 11 failures; three verified cycles, later pulses aborted. Minimum sampled heap 187,608 bytes, no reset/allocation failure, maximum loop gap 23 ms. Rejected. |
| SDK-default 8/32 buffers and aggregation, 344.9 s | One client plus final four-client bursts: 477 replies, 12 failures; no verified cycle because the first sequence timed out. Minimum heap 163,516 bytes, no allocation failure/reset, peak chip temperature 60.8 C. Rejected. |

The smaller retained profile performed best in short checks but still failed a
longer loaded run. It is retained as the least-regressive measured configuration,
not a proven cure. TX power remains the calibrated SDK default. Experimental
larger-buffer, lower-TX-power, and TX-aggregation-off changes are not retained.

During loaded traffic, the ESP32 answered 10 of 15 pings (33% packet loss,
8-735 ms successful latency). The router answered all 10 comparison pings at
3-7 ms. The laptop was on 5 GHz Wi-Fi. This establishes loss on the path to the
ESP32 beyond an app display problem, but cannot distinguish its radio/driver,
2.4 GHz interference, supply/cable, antenna layout, or defective hardware.

## What Passed

- Sixteen live HTTP checks: fragmented headers/body, overlong body/length/URI,
  malformed/duplicate lengths, chunked refusal, bounded header count, removed
  Terminal route, trickle deadline, and missing-LF deadline. The missing-LF case
  first failed on hardware, then passed after the deadline correction.
- Exact browser-origin preflights for `http://localhost:8765` and
  `http://127.0.0.1:8765`; an unlisted origin receives no CORS permission.
  The real browser app recovered to Online. These are private testing settings,
  not a public wildcard or a replacement for command authentication.
- Five USB-triggered Wi-Fi reconnects: 1.39-3.66 s recovery, same boot, output
  inactive, no failed allocation. This tests deliberate link cycling, not router
  shutdown or recovery from every associated-but-unresponsive radio fault.
- Ten seconds of inert USB flooding: 4,391,936 bytes sent, 19 successful HTTP
  checks during flooding, subsequent USB STATUS readable, no reset/allocation
  failure/output activation. No retained Terminal history exists.
- Eight native firmware suites; 32 Flutter tests; Flutter analysis and web build;
  nine release-metadata tests. Firmware build/image layout verification passed.
  Native mobile compilation and installed-door operation are separate checks.

## Diagnosis And Next Check

The older memory-pressure failure remains documented in the
[2026-10-01 diagnosis](CONNECTION_DIAGNOSIS_2026-10-01.md). This investigation
also reproduces an HTTP idle-peer stall exceeding the app's four-second budget.
Both have software mitigations in v2.2.0.

The remaining app-only failures occur with substantial heap margin, zero failed
allocations, no reboot, and a responsive main loop. Some occur while chip
temperature is steady around 57-61 C, so a heat-triggered shutdown has not been
demonstrated. The internal sensor does not measure the regulator or supply, and
no voltage/current or RF equipment was available. A steady red LED does not
rule out supply noise or radio failure.

### Online Research

- An [ESP3D Super Mini report](https://github.com/luc-github/ESP3D/issues/1009)
  describes working serial communication but failed Wi-Fi, with a lower TX
  setting helping the reporter's unnamed board. This is a first-hand report,
  not proof about this board. Our 8.5 dBm trial failed, so that workaround is
  not retained as a cure.
- [Espressif's hardware checklist](https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32c3/schematic-checklist.html)
  explains that transmit current spikes can disturb the analog 3.3 V rail and
  that RF matching is board-specific. Its 3.3 V supply guidance concerns the
  chip rail, not the development board's USB input. No rail measurements were
  taken here, so supply instability remains a hypothesis.
- An [independent Super Mini antenna comparison](https://peterneufeld.wordpress.com/2025/03/04/esp32-c3-supermini-antenna-modification/)
  reports improved reception after antenna changes. Board variants and test
  conditions differ; this supports comparing hardware, not blindly modifying
  the antenna of a door controller.

These sources make power/RF hardware worth isolating, but do not exclude
router interference, driver behavior, or remaining software faults. Do not
label the board defective or recommend soldering changes from these reports.

Next isolate hardware with the same firmware and location: change only the USB
cable/power source, then compare another ESP32-C3 if available. Keep the relay
disconnected. Do not change router settings for other users or replace hardware
solely on the basis of the LED. Respect the user's 15-minute session cap; there
is no 24-hour run or endurance-certification claim.

Saved Wi-Fi and the private app key were preserved; application-only flashes
used the existing app slot, without NVS erasure. Private backup files and test
logs stay outside the repository. The physical lock/contact state, inductive
interference, and manual/emergency access must still be checked before permanent
installation, per [relay wiring](RELAY_SETUP.md).
