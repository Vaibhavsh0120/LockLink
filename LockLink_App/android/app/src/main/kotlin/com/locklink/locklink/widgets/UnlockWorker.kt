package com.locklink.locklink.widgets

import android.app.KeyguardManager
import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

class UnlockWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result {
        val tappedAt = inputData.getLong("tappedAt", 0)
        val claimed = applicationContext.getSharedPreferences("widget_actions", Context.MODE_PRIVATE)
        val token = id.toString()
        // WorkManager can restart interrupted work. Never replay an unlock POST.
        if (runAttemptCount > 0 || claimed.getString("lastClaim", null) == token) {
            GateWidgetProvider.show(applicationContext, "Request interrupted. Check gate before retrying.", announce = true)
            return Result.success()
        }
        if (!claimed.edit().putString("lastClaim", token).commit()) return Result.failure()
        fun valid() = !isStopped && System.currentTimeMillis() - tappedAt in 0..15000
        val keyguard = applicationContext.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!valid()) {
            GateWidgetProvider.show(applicationContext, "Request expired. Tap again.", announce = true)
            return Result.success()
        }
        if (keyguard.isDeviceLocked) {
            GateWidgetProvider.show(applicationContext, "Unlock your phone, then tap again.", announce = true)
            return Result.success()
        }
        try {
            val config = WidgetConfigStore.load(applicationContext)
                ?: throw GateFailure("Open LockLink to set up widgets.")
            GateWidgetProvider.show(applicationContext, "Sending unlock request…")
            val message = GateClient.unlock(config) {
                valid() && !keyguard.isDeviceLocked && WidgetConfigStore.load(applicationContext) == config
            }
            GateWidgetProvider.show(applicationContext, message, announce = true)
        } catch (error: GateFailure) {
            GateWidgetProvider.show(applicationContext, error.displayMessage, announce = true)
        } catch (_: Exception) {
            GateWidgetProvider.show(applicationContext, "Cannot reach device. Check Wi-Fi and settings.", announce = true)
        }
        return Result.success()
    }
}
