package com.example.message_me

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class SmsLogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.example.message_me.SMS_SENT_BY_NATIVE") return

        val phone = intent.getStringExtra("phone") ?: return
        val callType = intent.getStringExtra("call_type") ?: return
        val message = intent.getStringExtra("message") ?: return

        Log.d("SmartPinger", "📝 SmsLogReceiver: $phone / $callType")

        try {
            val prefs = context.getSharedPreferences(
                "SmartPingerPrefs", Context.MODE_PRIVATE)

            // Read existing pending logs
            val existing = prefs.getStringSet(
                "pending_sms_logs", mutableSetOf())?.toMutableSet()
                ?: mutableSetOf()

            // Add new entry — phone|callType|message|timestamp
            val entry = "$phone|$callType|${message.replace("|", " ")}|${System.currentTimeMillis()}"
            existing.add(entry)

            prefs.edit().putStringSet("pending_sms_logs", existing).apply()
            Log.d("SmartPinger", "📝 Queued log: $entry")
        } catch (e: Exception) {
            Log.e("SmartPinger", "❌ Log queue failed: ${e.message}")
        }
    }
}