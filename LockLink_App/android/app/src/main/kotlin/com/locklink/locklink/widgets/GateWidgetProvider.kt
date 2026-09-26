package com.locklink.locklink.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import android.widget.Toast
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.locklink.locklink.R
import java.text.DateFormat
import java.util.Date

open class GateWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { render(context) }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != UNLOCK) return
        val work = OneTimeWorkRequestBuilder<UnlockWorker>()
            .setInputData(workDataOf("tappedAt" to System.currentTimeMillis())).build()
        val pending = goAsync()
        try {
            WorkManager.getInstance(context).enqueueUniqueWork("gate-unlock", ExistingWorkPolicy.KEEP, work)
                .result.addListener({ pending.finish() }, { command -> command.run() })
        } catch (_: Exception) {
            show(context, "Could not start request. Tap again.")
            pending.finish()
        }
    }

    companion object {
        const val UNLOCK = "com.locklink.locklink.WIDGET_UNLOCK"
        fun show(context: Context, message: String, announce: Boolean = false) {
            val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
            context.getSharedPreferences("widget_status", Context.MODE_PRIVATE).edit()
                .putString("message", "$message\n$time").apply()
            render(context)
            if (announce) Handler(Looper.getMainLooper()).post {
                Toast.makeText(context.applicationContext, message, Toast.LENGTH_LONG).show()
            }
        }
        fun compactStatus(message: String, circle: Boolean): String {
            val text = message.substringBefore('\n')
            val time = message.substringAfter('\n', "")
            val summary = when {
                text.contains("accepted") -> "Sent"
                text.startsWith("Sending") -> "Sending…"
                text.contains("No confirmation") || text.contains("interrupted") -> "Check gate"
                text.contains("already unlocking") -> "Active"
                text.contains("offline") || text.contains("Cannot reach") -> "Offline"
                text.contains("Unlock your phone") -> "Unlock phone"
                text.contains("expired") || text.contains("Could not start") -> "Tap again"
                text.contains("set up") || text.contains("Pairing") || text.contains("not armed") -> "Set up"
                text.startsWith("Ready") || text.contains("same Wi-Fi") -> if (circle) "Unlock" else "Same Wi-Fi"
                else -> "Check app"
            }
            if (circle) return when (summary) {
                "Unlock" -> "Gate"
                "Sending…", "Active" -> "Wait"
                "Check gate", "Check app" -> "Check"
                "Offline" -> "Wi-Fi"
                "Unlock phone" -> "Phone"
                "Tap again" -> "Retry"
                "Set up" -> "Setup"
                else -> summary
            }
            return if (summary in listOf("Sent", "Active") && time.isNotEmpty()) "$summary · $time" else summary
        }
        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val message = context.getSharedPreferences("widget_status", Context.MODE_PRIVATE)
                .getString("message", "Use the same Wi-Fi as your gate.")!!
            val intent = Intent(context, GateWidgetProvider::class.java).setAction(UNLOCK)
            val pending = PendingIntent.getBroadcast(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            for (provider in listOf(GateWidgetProvider::class.java, GateCircleWidgetProvider::class.java)) {
                val circle = provider == GateCircleWidgetProvider::class.java
                val views = RemoteViews(context.packageName, if (circle) R.layout.gate_widget_circle else R.layout.gate_widget)
                views.setTextViewText(R.id.widget_status, compactStatus(message, circle))
                views.setContentDescription(R.id.widget_unlock, "Unlock gate. Last result: $message")
                views.setOnClickPendingIntent(R.id.widget_unlock, pending)
                manager.updateAppWidget(manager.getAppWidgetIds(ComponentName(context, provider)), views)
            }
        }
    }
}

class GateCircleWidgetProvider : GateWidgetProvider()
