package com.nextracom.smartpinger

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.nextracom.smartpinger/settings"
    private val TAG = "SmartPinger"
    private val FLUTTER_PREFS = "FlutterSharedPreferences"
    private val NATIVE_PREFS = "SmartPingerPrefs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "openSimSettings" -> {
                        try {
                            startActivity(Intent(
                                Settings.ACTION_NETWORK_OPERATOR_SETTINGS))
                            result.success(null)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_SETTINGS))
                                result.success(null)
                            } catch (e2: Exception) {
                                result.error("ERROR", e2.message, null)
                            }
                        }
                    }

                    "openBatterySettings" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(
                                    Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("ERROR", e2.message, null)
                            }
                        }
                    }

                    "openIntent" -> {
                        try {
                            val args = call.arguments as Map<*, *>
                            val pkg = args["package"] as String
                            val activity = args["activity"] as String
                            val intent = if (activity.isNotEmpty()) {
                                Intent().apply {
                                    component = android.content.ComponentName(
                                        pkg, activity)
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                            } else {
                                packageManager.getLaunchIntentForPackage(pkg)
                                    ?: throw Exception("Package not found")
                            }
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "syncRules" -> {
                        try {
                            val args = call.arguments as? Map<*, *>
                            val nativePrefs = getSharedPreferences(
                                NATIVE_PREFS, MODE_PRIVATE)
                            val editor = nativePrefs.edit()

                            val missed = args?.get("missed") as? String
                            val incoming = args?.get("incoming") as? String
                            val outgoing = args?.get("outgoing") as? String
                            val enabled = args?.get("enabled") as? Boolean ?: false

                            if (missed != null) {
                                editor.putString("auto_sms_message_missed", missed)
                            } else {
                                editor.remove("auto_sms_message_missed")
                            }
                            if (incoming != null) {
                                editor.putString("auto_sms_message_incoming", incoming)
                            } else {
                                editor.remove("auto_sms_message_incoming")
                            }
                            if (outgoing != null) {
                                editor.putString("auto_sms_message_outgoing", outgoing)
                            } else {
                                editor.remove("auto_sms_message_outgoing")
                            }

                            editor.putBoolean("auto_trigger_enabled", enabled)
                            editor.apply()

                            Log.d(TAG, "✅ Rules synced to native prefs")
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ syncRules failed: ${e.message}")
                            result.error("ERROR", e.message, null)
                        }
                    }

                    "startCallDetection" -> {
                        try {
                            CallDetectionService.start(this)
                            Log.d(TAG, "✅ CallDetectionService started from Flutter")
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ✅ Send SMS via native SmsManager — replaces another_telephony
                    "sendSms" -> {
                        try {
                            val phone   = call.argument<String>("phone")
                            val message = call.argument<String>("message")
                            if (phone == null || message == null) {
                                result.error("INVALID_ARGS", "phone and message required", null)
                                return@setMethodCallHandler
                            }
                            val smsManager = if (android.os.Build.VERSION.SDK_INT >= 31) {
                                getSystemService(android.telephony.SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                android.telephony.SmsManager.getDefault()
                            }
                            val parts = smsManager.divideMessage(message)
                            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                            Log.d(TAG, "📤 SMS sent to $phone from Flutter channel")
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ sendSms failed: ${e.message}")
                            result.error("SMS_FAILED", e.message, null)
                        }
                    }

                    "stopCallDetection" -> {
                        try {
                            CallDetectionService.stop(this)
                            Log.d(TAG, "✅ CallDetectionService stopped from Flutter")
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    "clearDedupKeys" -> {
                        try {
                            val nativePrefs = getSharedPreferences(
                                NATIVE_PREFS, MODE_PRIVATE)
                            val editor = nativePrefs.edit()
                            val keys = nativePrefs.all.keys
                                .filter { it.startsWith("sent_") }
                            keys.forEach { editor.remove(it) }
                            editor.apply()
                            Log.d(TAG, "🧹 Cleared ${keys.size} dedup keys")
                            result.success(keys.size)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    "checkOverlayPermission" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this)
                        } else {
                            true
                        }
                        Log.d(TAG, "🔍 Overlay permission: $granted")
                        result.success(granted)
                    }

                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!Settings.canDrawOverlays(this)) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                        }
                        result.success(null)
                    }

                    "checkExactAlarmPermission" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                            alarmManager.canScheduleExactAlarms()
                        } else {
                            true
                        }
                        result.success(granted)
                    }

                    "requestExactAlarmPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        setupCrashHandler()
        createNotificationChannel()
        super.onCreate(savedInstanceState)
        syncFlutterPrefsToNative()
        handleIntent(intent)
        if (CallDetectionService.hasPhonePermission(this)) {
            CallDetectionService.start(this)
        }
    }

    override fun onResume() {
        super.onResume()
        syncFlutterPrefsToNative()
        if (CallDetectionService.hasPhonePermission(this)) {
            CallDetectionService.start(this)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun setupCrashHandler() {
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e(TAG, "💥 Uncaught exception in ${thread.name}", throwable)
            if (throwable.stackTrace.any {
                it.className.contains("CallDetectionService") }) {
                Log.e(TAG, "Service crashed — scheduling restart")
                Handler(Looper.getMainLooper()).postDelayed({
                    CallDetectionService.start(this)
                }, 2000)
            }
        }
    }

    private fun syncFlutterPrefsToNative() {
        try {
            val flutterPrefs = getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
            val nativePrefs = getSharedPreferences(NATIVE_PREFS, MODE_PRIVATE)
            val editor = nativePrefs.edit()

            Log.d(TAG, "=== Flutter prefs dump ===")
            flutterPrefs.all.forEach { (key, value) ->
                Log.d(TAG, "  KEY: '$key' = '$value' [${value?.javaClass?.simpleName}]")
            }
            Log.d(TAG, "==========================")

            val enabledRaw = flutterPrefs.all["flutter.auto_trigger_enabled"]
            val enabled = when (enabledRaw) {
                is Boolean -> enabledRaw
                is String -> enabledRaw.toBoolean()
                else -> false
            }
            editor.putBoolean("auto_trigger_enabled", enabled)
            Log.d(TAG, "🔄 auto_trigger_enabled synced: $enabled")

            for (callType in listOf("missed", "incoming", "outgoing")) {
                val msgRaw = flutterPrefs.all["flutter.auto_sms_message_$callType"]
                val msg = when (msgRaw) {
                    is String -> msgRaw
                    else -> null
                }
                if (!msg.isNullOrEmpty()) {
                    editor.putString("auto_sms_message_$callType", msg)
                    Log.d(TAG, "🔄 Message synced for $callType")
                } else {
                    editor.remove("auto_sms_message_$callType")
                }
            }

            editor.apply()
            Log.d(TAG, "✅ Sync complete — enabled: $enabled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Sync failed: ${e.message}")
        }
    }

    private fun handleIntent(intent: Intent?) {
        when (intent?.action) {
            "BOOT_START" -> {
                Log.d(TAG, "📱 Boot start — restarting services")
                CallDetectionService.start(this)
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel("auto_sms_channel") == null) {
                val channel = NotificationChannel(
                    "auto_sms_channel",
                    "Auto SMS Service",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Monitors calls for auto SMS replies"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }
}