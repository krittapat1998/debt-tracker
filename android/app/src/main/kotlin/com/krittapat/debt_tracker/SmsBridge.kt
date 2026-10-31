package com.krittapat.debt_tracker

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Implemented by MainActivity: runtime permissions need an Activity. */
interface SmsPermissionHost {
    fun smsPermissionStatus(): String
    fun requestSmsPermission(onResult: (Boolean) -> Unit)
    fun openAppSettings()
}

/**
 * Platform side of lib/platform/sms_gateway.dart.
 *
 * SMS never leave the device: they are only handed to the Dart parser
 * running in this app.
 */
object SmsBridge {
    private const val METHOD_CHANNEL = "debt_tracker/sms"
    private const val EVENT_CHANNEL = "debt_tracker/sms_events"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun register(context: Context, messenger: BinaryMessenger, permissions: SmsPermissionHost) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "permissionStatus" -> result.success(permissions.smsPermissionStatus())
                "requestPermission" -> permissions.requestSmsPermission { granted -> result.success(granted) }
                "openSettings" -> {
                    permissions.openAppSettings()
                    result.success(null)
                }
                "readInbox" -> {
                    val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                    val limit = call.argument<Number>("limit")?.toInt() ?: 500
                    Thread {
                        try {
                            val messages = readInbox(context, since, limit)
                            mainHandler.post { result.success(messages) }
                        } catch (e: SecurityException) {
                            mainHandler.post { result.error("PERMISSION_DENIED", e.message, null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("READ_FAILED", e.message, null) }
                        }
                    }.start()
                }
                "configure" -> {
                    SmsStore.configure(
                        context,
                        enabled = call.argument<Boolean>("enabled") ?: false,
                        senders = call.argument<List<String>>("senders") ?: emptyList(),
                        keywords = call.argument<List<String>>("keywords") ?: emptyList(),
                    )
                    result.success(null)
                }
                "takePending" -> result.success(SmsStore.takePending(context))
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    /** Sends a live SMS to Dart; returns false when the app is not listening. */
    fun emit(message: Map<String, Any>): Boolean {
        val sink = eventSink ?: return false
        mainHandler.post { sink.success(message) }
        return true
    }

    private fun readInbox(context: Context, sinceMillis: Long, limit: Int): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.DATE_SENT,
        )
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(sinceMillis.toString()),
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val address = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val dateSent = c.getColumnIndexOrThrow(Telephony.Sms.DATE_SENT)
            while (c.moveToNext() && out.size < limit) {
                val sent = c.getLong(dateSent)
                out.add(
                    mapOf(
                        "id" to c.getLong(id).toString(),
                        "sender" to (c.getString(address) ?: ""),
                        "body" to (c.getString(body) ?: ""),
                        // Same clock as SmsMessage.timestampMillis in the live
                        // receiver, so both paths de-duplicate to one key.
                        "timestamp" to if (sent > 0) sent else c.getLong(date),
                    ),
                )
            }
        }
        return out
    }
}
