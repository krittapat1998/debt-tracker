package com.krittapat.debt_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony

/**
 * Receives new SMS in real time. Bank-looking messages go straight to the
 * running app, or are queued locally with a "review it" notification when
 * the app is closed. Nothing is saved to the ledger without user review.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return

        // Multipart SMS arrive as several PDUs from the same sender.
        val bodies = LinkedHashMap<String, StringBuilder>()
        val times = HashMap<String, Long>()
        for (m in parts) {
            val sender = m.displayOriginatingAddress ?: m.originatingAddress ?: ""
            bodies.getOrPut(sender) { StringBuilder() }.append(m.displayMessageBody ?: m.messageBody ?: "")
            times.putIfAbsent(sender, m.timestampMillis)
        }

        var queued = 0
        for ((sender, body) in bodies) {
            val text = body.toString()
            if (!SmsStore.shouldCapture(context, sender, text)) continue
            val ts = times[sender] ?: System.currentTimeMillis()
            val message = mapOf<String, Any>(
                "id" to "rx-$ts",
                "sender" to sender,
                "body" to text,
                "timestamp" to ts,
            )
            if (!SmsBridge.emit(message)) {
                SmsStore.addPending(context, message)
                queued++
            }
        }
        if (queued > 0) notifyPending(context)
    }

    private fun notifyPending(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.sms_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val count = SmsStore.pendingCount(context)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_debt)
            .setContentTitle(context.getString(R.string.sms_notification_title))
            .setContentText(context.getString(R.string.sms_notification_text, count))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    companion object {
        private const val CHANNEL_ID = "sms_import"
        private const val NOTIFICATION_ID = 4242
    }
}
