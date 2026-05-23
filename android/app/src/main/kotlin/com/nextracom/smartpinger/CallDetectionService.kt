package com.nextracom.smartpinger

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class CallDetectionService : Service() {

    companion object {
        const val TAG = "SmartPinger"
        const val NATIVE_PREFS = "SmartPingerPrefs"
        private const val NOTIFICATION_ID = 889
        private const val CHANNEL_ID = "call_detection_channel"

        fun start(context: Context) {
            if (!hasPhonePermission(context)) {
                Log.d(TAG, "⚠️ Phone permission not granted — skipping")
                return
            }
            try {
                val intent = Intent(context, CallDetectionService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "✅ CallDetectionService start requested")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start: ${e.message}")
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(
                    Intent(context, CallDetectionService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to stop: ${e.message}")
            }
        }

        fun hasPhonePermission(context: Context): Boolean {
            return ContextCompat.checkSelfPermission(
                context, Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: TelephonyCallback? = null

    private var wakeLock: PowerManager.WakeLock? = null

    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var incomingNumber = ""
    private var savedNumber = ""
    private var wasIncoming = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "📡 CallDetectionService onCreate")

        createNotificationChannel()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            Log.d(TAG, "✅ startForeground called")
        } catch (e: Exception) {
            Log.e(TAG, "❌ startForeground failed: ${e.message}")
            stopSelf()
            return
        }

        acquireWakeLock()

        if (!hasPhonePermission(this)) {
            Log.e(TAG, "❌ No phone permission")
            stopSelf()
            return
        }

        telephonyManager =
            getSystemService(TELEPHONY_SERVICE) as TelephonyManager

        try {
            startListening()
            Log.d(TAG, "📡 Listening for calls")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start listening: ${e.message}")
            stopSelf()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopListening()
        releaseWakeLock()
        Log.d(TAG, "📡 Service destroyed — scheduling restart")
        scheduleRestart()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📡 onStartCommand")

        if (wakeLock?.isHeld == false) {
            acquireWakeLock()
        }

        if (telephonyManager == null && hasPhonePermission(this)) {
            telephonyManager =
                getSystemService(TELEPHONY_SERVICE) as TelephonyManager
            try {
                startListening()
            } catch (e: Exception) {
                Log.e(TAG, "Re-init listener failed: ${e.message}")
            }
        }

        return START_STICKY
    }

    private fun acquireWakeLock() {
        try {
            val powerManager =
                getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "SmartPinger::CallDetectionWakeLock"
            ).apply {
                acquire()
            }
            Log.d(TAG, "🔋 WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "❌ WakeLock failed: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d(TAG, "🔋 WakeLock released")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ WakeLock release failed: ${e.message}")
        }
    }

    private fun scheduleRestart() {
        try {
            val restartIntent = Intent(this, CallDetectionService::class.java)
            val pendingIntent = PendingIntent.getService(
                this, 1, restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 3000,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 3000,
                    pendingIntent
                )
            }
            Log.d(TAG, "⏰ Service restart scheduled in 3 seconds")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Restart schedule failed: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val manager = getSystemService(NotificationManager::class.java)
                if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                    val channel = NotificationChannel(
                        CHANNEL_ID,
                        "Call Detection",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "Monitors calls for auto SMS"
                        setShowBadge(false)
                        setSound(null, null)
                        enableVibration(false)
                        enableLights(false)
                    }
                    manager.createNotificationChannel(channel)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Channel creation failed: ${e.message}")
            }
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Smart Pinger")
            .setContentText("Monitoring calls for auto SMS")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setOngoing(true)
            .build()
    }

    private fun startListening() {
        val tm = telephonyManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(),
                TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleStateChange(state, savedNumber)
                }
            }
            tm.registerTelephonyCallback(mainExecutor, callback)
            telephonyCallback = callback

            @Suppress("DEPRECATION")
            val legacyListener = object : PhoneStateListener() {
                @Suppress("DEPRECATION")
                override fun onCallStateChanged(
                    state: Int, phoneNumber: String?) {
                    if (!phoneNumber.isNullOrEmpty()) {
                        savedNumber = phoneNumber
                        incomingNumber = phoneNumber
                    }
                }
            }
            @Suppress("DEPRECATION")
            tm.listen(legacyListener, PhoneStateListener.LISTEN_CALL_STATE)
            phoneStateListener = legacyListener

        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Suppress("DEPRECATION")
                override fun onCallStateChanged(
                    state: Int, phoneNumber: String?) {
                    if (!phoneNumber.isNullOrEmpty()) {
                        savedNumber = phoneNumber
                        incomingNumber = phoneNumber
                    }
                    handleStateChange(state, phoneNumber ?: savedNumber)
                }
            }
            @Suppress("DEPRECATION")
            tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            phoneStateListener = listener
        }
    }

    private fun stopListening() {
        try {
            val tm = telephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallback?.let {
                    tm?.unregisterTelephonyCallback(it)
                }
            }
            @Suppress("DEPRECATION")
            phoneStateListener?.let {
                tm?.listen(it, PhoneStateListener.LISTEN_NONE)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping listeners: ${e.message}")
        }
    }

    private fun handleStateChange(state: Int, number: String?) {
        val phone = when {
            !number.isNullOrEmpty() -> number
            incomingNumber.isNotEmpty() -> incomingNumber
            savedNumber.isNotEmpty() -> savedNumber
            else -> ""
        }

        Log.d(TAG, "📞 State: $state phone: $phone last: $lastState")

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                if (phone.isNotEmpty()) {
                    incomingNumber = phone
                    savedNumber = phone
                }
                wasIncoming = true
                lastState = TelephonyManager.CALL_STATE_RINGING
                Log.d(TAG, "📲 Ringing: $incomingNumber")
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (lastState == TelephonyManager.CALL_STATE_IDLE) {
                    wasIncoming = false
                    if (phone.isNotEmpty()) {
                        savedNumber = phone
                        incomingNumber = phone
                    }
                }
                lastState = TelephonyManager.CALL_STATE_OFFHOOK
            }

            TelephonyManager.CALL_STATE_IDLE -> {
                val finalNumber = incomingNumber.ifEmpty { savedNumber }

                when (lastState) {
                    TelephonyManager.CALL_STATE_RINGING -> {
                        Log.d(TAG, "📵 Missed: $finalNumber")
                        if (finalNumber.isNotEmpty()) {
                            triggerSms(finalNumber, "missed")
                        }
                    }
                    TelephonyManager.CALL_STATE_OFFHOOK -> {
                        val callType = if (wasIncoming) "incoming" else "outgoing"
                        Log.d(TAG, "📞 $callType ended: $finalNumber")
                        if (finalNumber.isNotEmpty()) {
                            triggerSms(finalNumber, callType)
                        }
                    }
                }

                lastState = TelephonyManager.CALL_STATE_IDLE
                incomingNumber = ""
                wasIncoming = false
            }
        }
    }

    private fun triggerSms(phone: String, callType: String) {
        try {
            val nativePrefs =
                getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
            val flutterPrefs = getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE)

            val enabledRaw =
                flutterPrefs.all["flutter.auto_trigger_enabled"]
            val enabledFromFlutter = when (enabledRaw) {
                is Boolean -> enabledRaw
                is String -> enabledRaw.toBoolean()
                else -> false
            }
            val enabledFromNative =
                nativePrefs.getBoolean("auto_trigger_enabled", false)
            val enabled = enabledFromFlutter || enabledFromNative

            Log.d(TAG, "🔍 enabled — flutter: $enabledFromFlutter " +
                "native: $enabledFromNative")

            if (!enabled) {
                Log.d(TAG, "⏭️ Auto SMS disabled")
                return
            }

            val sentKey = "sent_${phone}_${callType}_${getTodayKey()}"
            if (nativePrefs.getBoolean(sentKey, false)) {
                Log.d(TAG, "⏭️ Already sent to $phone for $callType today")
                return
            }

            val msgRaw =
                flutterPrefs.all["flutter.auto_sms_message_$callType"]
            val message = when (msgRaw) {
                is String -> msgRaw
                else -> null
            } ?: nativePrefs.getString("auto_sms_message_$callType", null)

            if (message.isNullOrEmpty()) {
                Log.d(TAG, "⚠️ No message for $callType")
                return
            }

            val smsManager = if (Build.VERSION.SDK_INT >= 31) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }

            val parts = smsManager.divideMessage(message)
            smsManager.sendMultipartTextMessage(
                phone, null, parts, null, null)
            Log.d(TAG, "📤 SMS sent to $phone ($callType)")

            nativePrefs.edit().putBoolean(sentKey, true).apply()

            try {
                val broadcastIntent = Intent(
                    "com.nextracom.smartpinger.SMS_SENT_BY_NATIVE"
                ).apply {
                    putExtra("phone", phone)
                    putExtra("call_type", callType)
                    putExtra("message", message)
                    setPackage(packageName)
                }
                sendBroadcast(broadcastIntent)
            } catch (e: Exception) {
                Log.d(TAG, "Broadcast failed: ${e.message}")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ SMS failed: ${e.message}")
        }
    }

    private fun getTodayKey(): String {
        val cal = java.util.Calendar.getInstance()
        return "${cal.get(java.util.Calendar.YEAR)}_" +
            "${cal.get(java.util.Calendar.DAY_OF_YEAR)}"
    }
}