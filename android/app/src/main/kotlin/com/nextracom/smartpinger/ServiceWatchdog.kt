package com.nextracom.smartpinger

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ServiceWatchdog : BroadcastReceiver() {

    companion object {
        const val TAG = "SmartPinger"
        const val ACTION = "com.nextracom.smartpinger.WATCHDOG"
        private const val INTERVAL_MS = 5 * 60 * 1000L // 5 minutes

        fun schedule(context: Context) {
            try {
                val alarmManager =
                    context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, ServiceWatchdog::class.java).apply {
                    action = ACTION
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

                // ✅ Cancel existing alarm first
                alarmManager.cancel(pendingIntent)

                // ✅ Use setExactAndAllowWhileIdle — works even in doze mode
                if (android.os.Build.VERSION.SDK_INT >=
                    android.os.Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        System.currentTimeMillis() + INTERVAL_MS,
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        System.currentTimeMillis() + INTERVAL_MS,
                        pendingIntent
                    )
                }
                Log.d(TAG, "⏰ Watchdog scheduled in 5 minutes")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Watchdog schedule failed: ${e.message}")
            }
        }

        fun cancel(context: Context) {
            try {
                val alarmManager =
                    context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, ServiceWatchdog::class.java).apply {
                    action = ACTION
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
                Log.d(TAG, "⏰ Watchdog cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Watchdog cancel failed: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "⏰ Watchdog fired — checking services")

        // ✅ Don't restart if subscription expired or user inactive
        val flutterPrefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE)

        val expiryRaw = flutterPrefs.all["flutter.subscription_expiry"]
        val isExpired = if (expiryRaw != null) {
            try {
                val formats = listOf(
                    "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                    "yyyy-MM-dd'T'HH:mm:ss'Z'",
                    "yyyy-MM-dd"
                )
                var expired = false
                for (format in formats) {
                    try {
                        val sdf = java.text.SimpleDateFormat(format, java.util.Locale.getDefault())
                        val date = sdf.parse(expiryRaw.toString())
                        if (date != null) { expired = date.before(java.util.Date()); break }
                    } catch (_: Exception) {}
                }
                expired
            } catch (_: Exception) { false }
        } else false

        val isActive = flutterPrefs.getBoolean("flutter.user_is_active", true)

        if (isExpired || !isActive) {
            Log.d(TAG, "⏰ Watchdog — subscription expired or inactive, NOT restarting service")
            // Cancel future watchdog alarms too
            cancel(context)
            return
        }

        // ✅ Only restart if subscription is valid and user is active
        if (CallDetectionService.hasPhonePermission(context)) {
            CallDetectionService.start(context)
            Log.d(TAG, "✅ Watchdog restarted CallDetectionService")
        }

        // ✅ Schedule next watchdog
        schedule(context)
    }
}