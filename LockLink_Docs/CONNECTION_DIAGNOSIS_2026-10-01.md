# Intermittent ESP32 connection diagnosis

Date: 2026-10-01, India Standard Time.

The repair is packaged as **v2.1.0** (app build **210**). The hardware runs below
used the repaired firmware before its version label was bumped from v2.0.1;
changing the release metadata does not change the tested connection logic.

## Finding

Intermittent loss of reachability was reproduced from the Windows PC independently
of the iPhone app. The reserved device address is correct. During a sustained
outage, the ESP32 still answered USB `STATUS`, reported Wi-Fi association and its
expected IPv4 address, and continued running without a new reset. Its local IP
connection nevertheless stopped answering HTTP and ping from the PC.

The user also checked `http://192.168.0.112/status` in iPhone Safari during the
outage and reported that it kept loading without opening. The failure therefore
also affects another client and an application independent of LockLink.

The later instrumented run demonstrated heap exhaustion: 14 failed allocations
and a minimum free heap of 244 bytes under repeated local traffic. Memory
pressure is therefore a confirmed fault requiring correction, although no
allocation callback was present during the original outage and a memory leak
has not been demonstrated. Router interoperability has not been fully excluded.

The app contributes a separate recovery problem: the committed implementation
shows Offline after the first failed status request, which has a four-second
deadline, and waits five seconds before its next automatic offline check.
Consequently, a temporary failure looks like a powered-off device and encourages
repeated manual refreshes. Restarting the app is not required by its polling
logic; it can simply coincide with a later successful request.

## Live observations

- COM7 identifies the attached board's USB serial interface. Firmware reports
  LockLink v2.0.1; the checkout targets `esp32-c3-supermini`.
- The PC uses `192.168.0.10`, with router `192.168.0.1`. At a successful check,
  `192.168.0.112` resolved to the ESP32-C3 MAC shown in the supplied reservation.
- Before serial monitoring, an HTTP request connected but received no response
  within five seconds. An initial ping run received two of four ESP32 replies;
  the router replied four of four times.
- Opening the first serial connection coincided with a USB-interface reset.
  Its reset reason must not be interpreted as a spontaneous brownout or crash.
  Subsequent readings showed increasing uptime without another observed reset.

| Run | HTTP status reads | ESP32 ping replies | Router ping replies | Timing |
| --- | --- | --- | --- | --- |
| Relay connected, later healthy interval | 32/32 succeeded | 31/32 | 32/32 | Longest HTTP response: 375 ms |
| Relay disconnected, USB only, user confirmed | 32/32 succeeded | 26/32 | 32/32 | HTTP responses: 47–2,312 ms |
| Subsequent USB-only sustained outage, no idle test connection | 0/10 succeeded | 0/10 | 10/10 | Each HTTP attempt timed out around four seconds |
| Recheck after more than 90 seconds without deliberate network probes | HTTP connection timed out | 0/2 | 2/2 | Still unreachable from the PC |

During the healthy runs, USB signal readings were approximately -52 to -57 dBm
and modem sleep was off. Free heap dropped during traffic and partly recovered
when traffic stopped. During the sustained outage, readings included 6,064 and
6,924 bytes; the later idle recheck reported 8,884 bytes. USB still reported the
expected address, association, modem sleep off, and inactive release output.

Disconnecting the relay did not eliminate the issue. Relay supply compatibility
and regulator loading still need the module's voltage/current specifications,
but relay power alone does not explain the reproduced USB-only outage. No relay
or unlock command was sent in this diagnosis.

## Firmware and transport assessment

Wi-Fi and LwIP allocate dynamic buffers from memory shared with the application.
The SDK defaults allow substantial dynamic Wi-Fi buffering and TCP windows of
about 5.7 KB. Inspection subsequently showed ArduinoMatter already lowers
Wi-Fi counts to four static RX and eight dynamic RX/TX buffers, with an RX
block-ack window of six. The old firmware also reserves about 10 KB for its
64-line terminal history, in addition to Matter, BLE and HTTP allocations.
Configured limits do not mean every buffer is allocated simultaneously.

`esp_get_free_heap_size()` reports aggregate free memory, not the largest block
that an allocation can use. Largest-block, minimum-heap and failed-allocation
diagnostics are needed to establish memory exhaustion or fragmentation.

The installed Arduino WebServer handles one active client and can wait five
seconds for an idle client's request. This exceeds the app's four-second
deadline. An idle-connection experiment was attempted, but its control request
already timed out and the later six-second request failed too. It therefore
does **not** establish that server serialization caused the original outage.
That mechanism also cannot by itself explain loss of ping/ARP reachability.

## App verification

Existing uncommitted edits, present before this investigation, add Connecting /
Reconnecting states and status retry delays of one second, then two seconds,
then five seconds. They also show a busy pending check. These changes were not
introduced in this diagnosis; the iPhone's installed build was not identified.

`flutter test --no-pub` passed all 74 tests; `flutter analyze --no-pub` passed.
The tests cover bounded startup recovery, recovery without replaying an unlock,
foreground revalidation, stale responses and device-authoritative release state.
They use mocked transport and do not prove physical Wi-Fi recovery or iPhone
socket behavior.

The user subsequently confirmed automatic connection and recovery on both cold
launch and return from the background with the updated firmware. Source checks
confirm Home polling pauses while Settings/Terminal is open, and Terminal
polling stops on leaving that page or entering the background. No additional
page-lifecycle changes were needed.

## Firmware correction and hardware verification

Terminal remains available and retains the latest 16 complete lines instead
of 64, preserving cursor/gap and per-line truncation semantics. Link maps show
the console's fixed footprint fell from 10,948 to 2,884 bytes: 8,064 bytes saved.
USB/authenticated `STATUS` reports minimum free heap, largest free block and
failed allocation counts. Its failure callback never allocates or prints.

The history-only image was tested for 325.8 seconds with 376 requests. Of these,
373 succeeded; three early Home reads timed out. Its final steady free heap was
18,480 bytes, but the lifetime minimum reached 244 bytes and it recorded 14
failed 2,312-byte allocations. Terminal traffic increased the failure count.
This image was not accepted as the final repair.

The next image initializes the Wi-Fi driver with two static RX buffers and
four dynamic RX/TX buffers. AMPDU RX is disabled, following Espressif's guidance
for fewer than six static RX buffers. The RX block-ack window is four, satisfying
driver constraints; other fields retain SDK defaults. Only driver allocation
limits are configured here: Matter still starts interfaces, restores saved
networks and manages reconnection. BLE commissioning remains available. This
trades bulk throughput for a bounded memory budget suitable for local control.

That image completed all 376 HTTP responses in 306.8 seconds with no timeouts
or allocation failures. Its final free heap was 23,496 bytes, largest block
12,788 bytes, and lifetime minimum 1,772 bytes. Three status replies were valid
HTTP 200 while the output was active; the initial harness incorrectly required
the locked state. The final harness accepts both documented states and records
them separately from transport failures. The deliberate idle peer delayed one
request to 4,703 ms, then the server recovered. A five-second server wait can
still exceed the app's four-second deadline, so bounded app retries remain needed.

Review found another avoidable memory peak in Terminal: retaining logs and
command output while allocating a second whole JSON response. The final source
uses a fixed 256-byte JSON serialization buffer, with identical counting and
sending passes and explicit Content-Length. History serialization reserves
once and checks every append before executing any command. A focused native
regression checks escaping, UTF-8, maximum cursor, large output, matching length
and sink failure. All seven native suites pass. Short socket writes stop the
connection and stop serialization rather than discarding an unsent suffix.

The final image completed **376/376 requests in 316.6 seconds**, including
240 Home status reads, challenge reads, a 60-second idle gap, 40 authenticated
Terminal exchanges (with repeated `STATUS` and full-history reads), one
deliberate idle peer, and 40 final Home reads. All Terminal responses parsed
as complete JSON with the expected schema. There were **zero allocation
failures**, no request timeouts, and uptime increased continuously. Final
free heap was **23,284 bytes**, largest block **12,276 bytes**, and the reported
lifetime minimum was **4,964 bytes**, versus 244 bytes in the history-only run.
The slowest response was 3,078 ms. This bounded comparison demonstrates that
the allocation failure reproduced earlier did not recur under the final test
load; it does not prove every router, traffic pattern or pairing operation.

PlatformIO built the final C3 image successfully (static RAM 89,976 bytes;
flash 1,841,879 bytes). The final application-only flash was hash-verified.
Fresh-context review found no remaining concrete issue in the final changes.

A full 4 MB device backup and the actual partition table were read before
programming. The application starts at `0x20000`; NVS starts at `0x10000`.
Only the application image was flashed and hash-verified. Saved Wi-Fi, app
key and Matter storage were not erased. The relay remained disconnected and
the diagnostic tools sent no release or pairing-changing commands.

## Recovery behavior retained

1. Keep allocation diagnostics available through `STATUS` for future faults.
2. Keep the reduced history and bounded allocations; verify repeated status
   and Terminal reads, idle gaps and phone reopen cycles on the physical board.
3. Keep the app's bounded read-only recovery behavior. Retain disabled control
   until a fresh response succeeds. Never automatically resend an uncertain
   unlock or pairing command.

Simply increasing the app timeout would not repair the sustained loss of
network reachability observed here.

## References and limits

- [ESP-IDF Wi-Fi memory and buffer guidance](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-guides/wifi-driver/wifi-performance-and-power-save.html)
- [ESP-IDF heap APIs](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/misc_system_api.html)
- [Heap allocation and largest-block diagnostics](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/mem_alloc.html)
- [ESP32-C3 supply design guidance](https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32c3/schematic-checklist.html)
- [Dart HTTP request cancellation](https://github.com/dart-lang/http/blob/master/pkgs/http/README.md)

Hardware results cover the USB-powered board with its relay disconnected.
Physical relay behavior, fresh Matter commissioning, router loss/rejoin and
long-duration behavior need separate checks. The iPhone installation and native
lifecycle were not directly instrumented; phone reopen results are user-reported.
