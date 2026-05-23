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

        // ✅ Restart CallDetectionService if needed
        if (CallDetectionService.hasPhonePermission(context)) {
            CallDetectionService.start(context)
            Log.d(TAG, "✅ Watchdog restarted CallDetectionService")
        }

        // ✅ Schedule next watchdog
        schedule(context)
    }
}