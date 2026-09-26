package com.locklink.locklink

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Build
import com.locklink.locklink.widgets.GateConfig
import com.locklink.locklink.widgets.GateWidgetProvider
import com.locklink.locklink.widgets.WidgetConfigStore

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
