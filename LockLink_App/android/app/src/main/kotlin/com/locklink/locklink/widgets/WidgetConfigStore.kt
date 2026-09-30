package com.locklink.locklink.widgets

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class GateConfig(val address: String, val signingKey: String) {
    init {
        val uri = URI(address)
        val host = uri.host.orEmpty().lowercase()
        val segments = host.split('.')
        val parts = segments.map { it.toIntOrNull() }
        val ipv4 = parts.size == 4 && parts.all { it != null && it in 0..255 } &&
            segments.indices.all { segments[it] == parts[it].toString() }
        val local = host == "localhost" || host.endsWith(".local") || (ipv4 &&
            (parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) ||
             (parts[0] == 172 && parts[1]!! in 16..31)))
        require(uri.scheme == "http" && local && (uri.port == -1 || uri.port in 1..65535) && uri.userInfo == null &&
            uri.rawQuery == null && uri.fragment == null && uri.path.orEmpty().isEmpty())
        require(signingKey.matches(Regex("[0-9a-fA-F]{64}")))
    }
}

object WidgetConfigStore {
    private const val ALIAS = "locklink_widget_config"
    private fun prefs(context: Context) = context.getSharedPreferences(ALIAS, Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    @Synchronized fun save(context: Context, config: GateConfig) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val json = JSONObject().put("address", config.address).put("key", config.signingKey)
        val encrypted = cipher.doFinal(json.toString().toByteArray(Charsets.UTF_8))
        check(prefs(context).edit()
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("data", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
    }

    @Synchronized fun load(context: Context): GateConfig? {
        val data = prefs(context).getString("data", null) ?: return null
        val iv = prefs(context).getString("iv", null) ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
        val json = JSONObject(String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), Charsets.UTF_8))
        return GateConfig(json.getString("address"), json.getString("key"))
    }

    @Synchronized fun clear(context: Context) { check(prefs(context).edit().clear().commit()) }
}
