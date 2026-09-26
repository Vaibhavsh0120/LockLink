package com.locklink.locklink.widgets

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.io.ByteArrayOutputStream
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class GateFailure(val displayMessage: String) : Exception(displayMessage)

object GateClient {
    fun signature(key: String, nonce: String): String {
        require(key.matches(Regex("[0-9a-fA-F]{64}")))
        require(nonce.matches(Regex("[0-9a-f]{32}")))
        val bytes = key.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(bytes, "HmacSHA256"))
        return mac.doFinal("unlock:$nonce".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    fun unlock(config: GateConfig, canSend: () -> Boolean): String {
        val status = request(config.address, "/status")
        if (!status.optBoolean("online", false)) throw GateFailure("Device offline. Check Wi-Fi.")
        if (status.optString("state") == "unlocking") throw GateFailure("Gate is already unlocking.")
        val headers = mutableMapOf<String, String>()
        when (status.optString("mode", "led")) {
            "relay" -> {
                if (!status.optBoolean("armed", false)) throw GateFailure("Device not armed. Check setup.")
                val nonce = request(config.address, "/challenge").getString("nonce")
                headers["X-LockLink-Nonce"] = nonce
                headers["X-LockLink-Signature"] = signature(config.signingKey, nonce)
            }
            "led" -> Unit
            else -> throw GateFailure("Unsupported device mode.")
        }
        if (!canSend()) throw GateFailure("Request expired. Tap again.")
        val result = try {
            request(config.address, "/unlock", headers)
        } catch (failure: GateFailure) {
            throw failure
        } catch (_: Exception) {
            throw GateFailure("No confirmation. Check gate before retrying.")
        }
        if (!result.optBoolean("success") || result.optString("state") != "unlocking" ||
            result.optInt("duration_ms", -1) < 0) {
            throw GateFailure("No confirmation. Check gate before retrying.")
        }
        return if (status.optString("mode", "led") == "relay") "Unlock command accepted." else "LED command accepted."
    }

    private fun request(address: String, path: String, headers: Map<String, String>? = null): JSONObject {
        val connection = URI(address + path).toURL().openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 3500
            connection.readTimeout = 3500
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.requestMethod = if (headers == null) "GET" else "POST"
            headers?.forEach { (key, value) -> connection.setRequestProperty(key, value) }
            if (headers != null) {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(0)
                connection.outputStream.close()
            }
            when (connection.responseCode) {
                200 -> Unit
                401 -> throw GateFailure("Pairing key rejected. Update settings.")
                409 -> throw GateFailure("Gate is already unlocking.")
                503 -> throw GateFailure("Device not armed. Check setup.")
                else -> throw GateFailure(if (headers == null) "Device refused the request."
                    else "No confirmation. Check gate before retrying.")
            }
            val bytes = connection.inputStream.use { stream ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(1024)
                while (output.size() <= 8192) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            if (bytes.size > 8192) throw GateFailure(if (headers == null) "Unexpected device response."
                else "No confirmation. Check gate before retrying.")
            return JSONObject(String(bytes, Charsets.UTF_8))
        } finally {
            connection.disconnect()
        }
    }
}
