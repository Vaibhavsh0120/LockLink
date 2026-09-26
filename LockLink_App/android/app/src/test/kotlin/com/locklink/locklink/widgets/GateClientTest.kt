package com.locklink.locklink.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.net.ServerSocket
import kotlin.concurrent.thread
import java.util.concurrent.atomic.AtomicInteger

class GateClientTest {
    private val key = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

    @Test fun signatureMatchesFirmwareAndFlutterVector() {
        assertEquals("341a767596290df094f966447190fec7ad24056bae49ea7dd64767a5e3774b75",
            GateClient.signature(key, "00112233445566778899aabbccddeeff"))
    }

    @Test fun rejectsMalformedChallengeAndRawPairingText() {
        assertThrows(IllegalArgumentException::class.java) { GateClient.signature(key, "bad-nonce") }
        assertThrows(IllegalArgumentException::class.java) { GateClient.signature("1234", "00112233445566778899aabbccddeeff") }
    }

    @Test fun allowsOnlyBareLocalHttpAddresses() {
        listOf("http://192.168.0.111", "http://10.1.2.3:8080", "http://gate.local").forEach { GateConfig(it, key) }
        listOf("http://8.8.8.8", "http://192.168.0.111/unlock", "http://user@192.168.0.111",
            "http://10.foo.0.0.1", "http://192.168.0.111?x=1").forEach {
            assertThrows(IllegalArgumentException::class.java) { GateConfig(it, key) }
        }
    }

    @Test fun ambiguousPostResponsesNeverClaimRejectionOrRetry() {
        listOf(200 to "x".repeat(9000), 200 to "[]", 500 to "{}").forEach { (code, body) ->
            val posts = AtomicInteger()
            val server = ServerSocket(0, 8, java.net.InetAddress.getByName("localhost"))
            val serving = thread(isDaemon = true) {
                repeat(3) {
                    server.accept().use { socket ->
                        val input = socket.getInputStream().bufferedReader()
                        val request = input.readLine()
                        while (!input.readLine().isNullOrEmpty()) { }
                        val isPost = request.startsWith("POST ")
                        if (isPost) posts.incrementAndGet()
                        val payload = if (isPost) body else """{"online":true,"state":"locked","mode":"led"}"""
                        val bytes = payload.toByteArray()
                        val responseCode = if (isPost) code else 200
                        socket.getOutputStream().apply {
                            write("HTTP/1.1 $responseCode Response\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
                            write(bytes)
                            flush()
                        }
                    }
                }
            }
            try {
                val error = assertThrows(GateFailure::class.java) {
                    GateClient.unlock(GateConfig("http://localhost:${server.localPort}", key)) { true }
                }
                assertEquals("No confirmation. Check gate before retrying.", error.displayMessage)
                assertEquals(1, posts.get())
                assertThrows(GateFailure::class.java) {
                    GateClient.unlock(GateConfig("http://localhost:${server.localPort}", key)) { false }
                }
                assertEquals("Expired or changed configuration must not send POST", 1, posts.get())
            } finally { server.close(); serving.join(1000) }
        }
    }
}
