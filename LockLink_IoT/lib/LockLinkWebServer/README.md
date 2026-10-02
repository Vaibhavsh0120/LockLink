# LockLink's bounded WebServer

This is the WebServer library shipped with the pinned Arduino-ESP32 3.3.12
framework, copied locally so no shared SDK package is modified. Original source
copyright and LGPL notices are retained.

Local changes bound idle waits to 1,500 ms, headers to 1,024 bytes / 1 second,
protocol lines to 512 bytes, targets to 256 bytes and plain command bodies to
128 bytes / 1 second. Bodies allocate once, read only their declared length,
and enforce a total deadline across TCP fragments. Form/file uploads are refused.
Client sockets close explicitly when requests finish or Wi-Fi restarts.
Active response and parser-error writes use nonblocking socket sends with a
shared one-second budget per header/body, including partial-write retries.
They bypass the SDK writer's repeated one-second waits under backpressure.
Counters distinguish idle receive timeouts from rejected/incomplete requests.
The listen queue holds eight pending clients. Body-bearing methods refuse
invalid/duplicate Content-Length and Transfer-Encoding. An empty urlencoded POST
is accepted for Android widget compatibility; nonempty forms and multipart
requests are refused. The local API has no uploads, streaming, or chunked-response
routes; unused upstream streaming helpers are not covered by the send budget.

Keep these changes when upgrading the framework, and rerun the physical
fragmented-request and incomplete-peer tests in `tools/stress_device.py`.
