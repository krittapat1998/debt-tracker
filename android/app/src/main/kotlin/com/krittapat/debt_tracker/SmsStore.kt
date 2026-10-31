package com.krittapat.debt_tracker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Local queue for bank SMS that arrive while the app is closed, plus the
 * filter that decides which SMS are worth keeping at all.
 */
object SmsStore {
    private const val PREFS = "debt_tracker_sms"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_SENDERS = "senders"
    private const val KEY_KEYWORDS = "keywords"
    private const val KEY_PENDING = "pending"
    private const val MAX_PENDING = 100

    private val otp = Regex("""\bOTP\b|รหัส\s*OTP|รหัสผ่าน|รหัสยืนยัน|verification code""", RegexOption.IGNORE_CASE)

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun configure(context: Context, enabled: Boolean, senders: List<String>, keywords: List<String>) {
        prefs(context).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putString(KEY_SENDERS, JSONArray(senders).toString())
            .putString(KEY_KEYWORDS, JSONArray(keywords).toString())
            .apply()
    }

    private fun list(context: Context, key: String): List<String> {
        val raw = prefs(context).getString(key, null) ?: return emptyList()
        val arr = JSONArray(raw)
        return (0 until arr.length()).map { arr.getString(it) }
    }

    /** Known bank sender, or a body with a statement/payment keyword. Never OTPs. */
    fun shouldCapture(context: Context, sender: String, body: String): Boolean {
        if (!prefs(context).getBoolean(KEY_ENABLED, false)) return false
        if (otp.containsMatchIn(body)) return false
        val s = sender.trim().lowercase()
        val senderMatch = list(context, KEY_SENDERS).any {
            val id = it.lowercase()
            s == id || s.startsWith(id)
        }
        return senderMatch || list(context, KEY_KEYWORDS).any { body.contains(it, ignoreCase = true) }
    }

    @Synchronized
    fun addPending(context: Context, message: Map<String, Any>) {
        val arr = JSONArray(prefs(context).getString(KEY_PENDING, "[]"))
        arr.put(JSONObject(message))
        val trimmed = JSONArray()
        val start = maxOf(0, arr.length() - MAX_PENDING)
        for (i in start until arr.length()) trimmed.put(arr.get(i))
        prefs(context).edit().putString(KEY_PENDING, trimmed.toString()).apply()
    }

    @Synchronized
    fun takePending(context: Context): List<Map<String, Any>> {
        val arr = JSONArray(prefs(context).getString(KEY_PENDING, "[]"))
        prefs(context).edit().remove(KEY_PENDING).apply()
        return (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            mapOf(
                "id" to o.optString("id"),
                "sender" to o.optString("sender"),
                "body" to o.optString("body"),
                "timestamp" to o.optLong("timestamp"),
            )
        }
    }

    fun pendingCount(context: Context): Int =
        JSONArray(prefs(context).getString(KEY_PENDING, "[]")).length()
}
