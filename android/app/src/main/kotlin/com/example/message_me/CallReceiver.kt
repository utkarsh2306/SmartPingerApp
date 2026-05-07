package com.example.message_me

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager
import android.telephony.SmsManager
import android.util.Log

class CallReceiver : BroadcastReceiver() {

    companion object {
        const val FLUTTER_PREFS = "FlutterSharedPreferences"
        const val NATIVE_PREFS = "SmartPingerPrefs"
        const val TAG = "SmartPinger"

        private var lastCallState = TelephonyManager.CALL_STATE_IDLE
        private var incomingNumber = ""
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""

        Log.d(TAG, "📞 CallReceiver state: $state number: $number")

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                if (number.isNotEmpty()) incomingNumber = number
                lastCallState = TelephonyManager.CALL_STATE_RINGING
                Log.d(TAG, "📲 Ringing: $incomingNumber")
            }

            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                lastCallState = TelephonyManager.CALL_STATE_OFFHOOK
                Log.d(TAG, "✅ Offhook")
            }

            TelephonyManager.EXTRA_STATE_IDLE -> {
                when (lastCallState) {
                    TelephonyManager.CALL_STATE_RINGING -> {
                        Log.d(TAG, "📵 Missed call: $incomingNumber")
                        if (incomingNumber.isNotEmpty()) {
                            sendAutoSms(context, incomingNumber, "missed")
                        }
                    }
                    TelephonyManager.CALL_STATE_OFFHOOK -> {
                        Log.d(TAG, "📞 Incoming ended: $incomingNumber")
                        if (incomingNumber.isNotEmpty()) {
                            sendAutoSms(context, incomingNumber, "incoming")
                        }
                    }
                }
                lastCallState = TelephonyManager.CALL_STATE_IDLE
                incomingNumber = ""
            }
        }
    }

    private fun isAutoSmsEnabled(context: Context): Boolean {
        val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val nativePrefs = context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

        val enabledRaw = flutterPrefs.all["flutter.auto_trigger_enabled"]
        val fromFlutter = when (enabledRaw) {
            is Boolean -> enabledRaw
            is String -> enabledRaw.toBoolean()
            else -> false
        }
        val fromNative = nativePrefs.getBoolean("auto_trigger_enabled", false)

        Log.d(TAG, "🔍 CallReceiver enabled — flutter: $fromFlutter native: $fromNative")
        return fromFlutter || fromNative
    }

    private fun getSmsMessage(context: Context, callType: String): String? {
        val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val nativePrefs = context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

        val msgRaw = flutterPrefs.all["flutter.auto_sms_message_$callType"]
        val fromFlutter = when (msgRaw) {
            is String -> msgRaw
            else -> null
        }
        if (!fromFlutter.isNullOrEmpty()) return fromFlutter

        return nativePrefs.getString("auto_sms_message_$callType", null)
    }

    private fun sendAutoSms(context: Context, phone: String, callType: String) {
        if (!isAutoSmsEnabled(context)) {
            Log.d(TAG, "⏭️ Auto SMS disabled")
            return
        }

        val nativePrefs = context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
        val sentKey = "sent_${phone}_${callType}_${getTodayKey()}"
        if (nativePrefs.getBoolean(sentKey, false)) {
            Log.d(TAG, "⏭️ Already sent to $phone for $callType today")
            return
        }

        val message = getSmsMessage(context, callType)
        if (message.isNullOrEmpty()) {
            Log.d(TAG, "⚠️ No message for $callType")
            return
        }

        try {
            val smsManager = if (Build.VERSION.SDK_INT >= 31) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val parts = smsManager.divideMessage(message)
            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            Log.d(TAG, "📤 CallReceiver SMS sent to $phone ($callType)")

            nativePrefs.edit().putBoolean(sentKey, true).apply()

            // ✅ Broadcast — no app opening
            notifyFlutter(context, phone, callType, message)

        } catch (e: Exception) {
            Log.e(TAG, "❌ SMS failed: ${e.message}")
        }
    }

    private fun notifyFlutter(
        context: Context,
        phone: String,
        callType: String,
        message: String
    ) {
        try {
            val intent = Intent("com.example.message_me.SMS_SENT_BY_NATIVE").apply {
                putExtra("phone", phone)
                putExtra("call_type", callType)
                putExtra("message", message)
                setPackage(context.packageName)
            }
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.d(TAG, "Broadcast failed: ${e.message}")
        }
    }

    private fun getTodayKey(): String {
        val cal = java.util.Calendar.getInstance()
        return "${cal.get(java.util.Calendar.YEAR)}_${cal.get(java.util.Calendar.DAY_OF_YEAR)}"
    }
}