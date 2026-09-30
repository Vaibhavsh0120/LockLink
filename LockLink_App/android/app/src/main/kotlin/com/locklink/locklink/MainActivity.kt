package com.locklink.locklink

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.locklink.locklink.widgets.GateConfig
import com.locklink.locklink.widgets.GateWidgetProvider
import com.locklink.locklink.widgets.WidgetConfigStore

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.locklink/home_apps")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val ecosystem = call.argument<String>("ecosystem")
                val target = when (ecosystem) {
                    "google" -> "com.google.android.apps.chromecast.app"
                    "alexa" -> "com.amazon.dee.app"
                    else -> null
                }
                if (target == null) {
                    result.success("unavailable")
                    return@setMethodCallHandler
                }
                // Google documents this Play Services entry point for Matter.
                // Never put a setup credential into an app URL, log or preference.
                val qr = call.argument<String>("pairingQr")
                if (ecosystem == "google" && qr != null && qr.length <= 512 &&
                    qr.matches(Regex("MT:[A-Z0-9.-]{19,}"))) {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(qr))
                            .setPackage("com.google.android.gms"))
                        result.success("setup")
                        return@setMethodCallHandler
                    } catch (_: ActivityNotFoundException) {
                        // Older or missing Play Services: open Home for manual setup.
                    } catch (_: SecurityException) {
                        // A blocked system entry point also permits manual setup.
                    }
                }
                try {
                    val intent = packageManager.getLaunchIntentForPackage(target)
                    if (intent == null) result.success("unavailable")
                    else {
                        startActivity(intent)
                        result.success("opened")
                    }
                } catch (_: ActivityNotFoundException) {
                    result.success("unavailable")
                } catch (_: SecurityException) {
                    result.success("unavailable")
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.locklink/widgets")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> {
                            val config = GateConfig(
                                requireNotNull(call.argument<String>("address")),
                                requireNotNull(call.argument<String>("signingKey")))
                            val previous = runCatching { WidgetConfigStore.load(this) }.getOrNull()
                            WidgetConfigStore.save(this, config)
                            if (previous != config) GateWidgetProvider.show(this, "Ready. Use the same Wi-Fi as your gate.")
                            else GateWidgetProvider.render(this)
                            result.success(null)
                        }
                        "clear" -> {
                            WidgetConfigStore.clear(this)
                            GateWidgetProvider.show(this, "Open LockLink to set up widgets.")
                            result.success(null)
                        }
                        "requestPin" -> {
                            val manager = AppWidgetManager.getInstance(this)
                            result.success(Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported &&
                                manager.requestPinAppWidget(ComponentName(this, GateWidgetProvider::class.java), null, null))
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("widget_setup", "Widget setup failed. Reopen LockLink and try again.", null)
                }
            }
    }
}
