package com.example.message_me

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
   override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
        Intent.ACTION_BOOT_COMPLETED,
        "android.intent.action.QUICKBOOT_POWERON",
        "com.htc.intent.action.QUICKBOOT_POWERON" -> {
            Log.d("SmartPinger", "📱 Boot — starting services")
            CallDetectionService.start(context)
            ServiceWatchdog.schedule(context) // ✅
        }
        Intent.ACTION_SCREEN_ON,
        Intent.ACTION_USER_PRESENT -> {
            Log.d("SmartPinger", "📱 Screen on — ensuring services")
            CallDetectionService.start(context)
            ServiceWatchdog.schedule(context) // ✅
        }
    }
}
}