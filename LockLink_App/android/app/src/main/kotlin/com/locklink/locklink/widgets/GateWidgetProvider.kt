package com.locklink.locklink.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.locklink.locklink.R
import java.text.DateFormat
import java.util.Date

class GateWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { render(context) }

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
        fun show(context: Context, message: String) {
            val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
            context.getSharedPreferences("widget_status", Context.MODE_PRIVATE).edit()
                .putString("message", "$message\n$time").apply()
            render(context)
        }
        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, GateWidgetProvider::class.java))
            val views = RemoteViews(context.packageName, R.layout.gate_widget)
            views.setTextViewText(R.id.widget_status,
                context.getSharedPreferences("widget_status", Context.MODE_PRIVATE)
                    .getString("message", "Use the same Wi-Fi as your gate."))
            val intent = Intent(context, GateWidgetProvider::class.java).setAction(UNLOCK)
            val pending = PendingIntent.getBroadcast(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_unlock, pending)
            manager.updateAppWidget(ids, views)
        }
    }
}
