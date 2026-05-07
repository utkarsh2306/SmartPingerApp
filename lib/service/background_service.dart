import 'dart:async';
import 'dart:ui';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/notification_service.dart';
import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const nativeChannel = MethodChannel('com.example.message_me/native_events');
  nativeChannel.setMethodCallHandler((call) async {
    if (call.method == 'smsSentByNative') {
      final args = call.arguments as Map;
      final phone = args['phone'] as String?;
      final callType = args['call_type'] as String?;
      final message = args['message'] as String?;
      if (phone != null && message != null && callType != null) {
        await _logAutoSms(phone, message, callType, null);
        print('📝 Logged native SMS for $phone');
      }
    }
  });
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stop').listen((event) {
    service.stopSelf();
  });

  // ✅ Sync rules to native on service start
  await _syncRulesToNative();

  // Poll calls every 10 seconds
  Timer.periodic(const Duration(seconds: 10), (_) async {
    await _checkForNewCalls();
  });

  // Process scheduled SMS every 30 seconds
  Timer.periodic(const Duration(seconds: 30), (_) async {
    await _processPendingScheduledSms();
  });

  // Clean SMS log every 24 hours
  Timer.periodic(const Duration(hours: 24), (_) async {
    await _cleanDailySmsLog();
    // Re-sync rules daily too
    await _syncRulesToNative();
  });

  // Update notification every minute
  Timer.periodic(const Duration(minutes: 1), (_) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Auto SMS Active',
        content:
            'Monitoring calls • ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      );
    }
  });
}

// ─── Native sync ─────────────────────────────────────────────────

// ✅ Updated signature — takes enabled as parameter
Future<void> _syncRulesToNative({bool? enabled}) async {
  try {
    final db = await DatabaseService.db;
    final prefs = await SharedPreferences.getInstance();

    // ✅ Use passed value OR read from prefs as fallback
    final isEnabled = enabled ?? prefs.getBool('auto_trigger_enabled') ?? false;

    for (final callType in ['missed', 'incoming', 'outgoing']) {
      final rules = await db.query(
        'auto_sms_rules',
        where: 'trigger_type = ? AND is_active = 1',
        whereArgs: [callType],
        limit: 1,
        orderBy: 'created_at DESC',
      );

      if (rules.isEmpty) {
        await prefs.remove('auto_sms_message_$callType');
        print('📝 Cleared native rule for $callType');
        continue;
      }

      final rule = rules.first;
      String message = '';

      final customMsg = rule['custom_message'] as String?;
      if (customMsg != null && customMsg.isNotEmpty) {
        message = customMsg;
      } else {
        final templateId = rule['template_id'] as int?;
        if (templateId != null) {
          final templates = await db.query(
            'templates',
            where: 'id = ?',
            whereArgs: [templateId],
          );
          if (templates.isNotEmpty) {
            message = templates.first['message'] as String? ?? '';
          }
        }
      }

      if (message.isNotEmpty) {
        await prefs.setString('auto_sms_message_$callType', message);
        print('📝 Synced native rule for $callType: $message');
      } else {
        await prefs.remove('auto_sms_message_$callType');
      }
    }

    // ✅ Write enabled flag
    await prefs.setBool('auto_trigger_enabled', isEnabled);
    print('📝 Native sync complete — enabled: $isEnabled');
  } catch (e) {
    print('❌ Error syncing rules to native: $e');
  }
}

Future<void> _cleanDailySmsLog() async {
  final db = await DatabaseService.db;
  final yesterday = DateTime.now()
      .subtract(const Duration(hours: 24))
      .millisecondsSinceEpoch;
  final deleted = await db.delete(
    'sms_sent_log',
    where: 'sent_at < ?',
    whereArgs: [yesterday],
  );

  // ✅ Also clear native SharedPreferences dedup keys older than today
  try {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('sent_')).toList();

    final todayKey = _getTodayKey();
    for (final key in keys) {
      if (!key.contains(todayKey)) {
        await prefs.remove(key);
      }
    }
  } catch (e) {
    print('⚠️ Could not clean native prefs: $e');
  }

  if (deleted > 0) print('🧹 Cleaned $deleted old sms_sent_log entries');
}

String _getTodayKey() {
  final now = DateTime.now();
  return '${now.year}_${now.month}_${now.day}';
}

// ─── Call checking ────────────────────────────────────────────────

Future<void> _checkForNewCalls() async {
  try {
    final allLogs = await CallLog.get();
    final fiveMinutesAgo = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;

    final recentCalls = allLogs.where((call) {
      return call.timestamp != null && call.timestamp! >= fiveMinutesAgo;
    }).toList();

    if (recentCalls.isEmpty) return;

    print('📞 ${recentCalls.length} recent calls found');

    for (var call in recentCalls) {
      if (call.number == null || call.number!.isEmpty) continue;
      if (call.timestamp == null) continue;

      final isProcessed = await _isCallProcessed(call);
      if (!isProcessed) {
        print('✅ New call: ${call.number} (${call.callType})');
        await _processNewCall(call);
        await _markCallProcessed(call);
      }
    }
  } catch (e) {
    print('❌ Error checking calls: $e');
  }
}

Future<bool> _isCallProcessed(CallLogEntry call) async {
  try {
    final db = await DatabaseService.db;
    final result = await db.query(
      'processed_calls',
      where: 'call_id = ?',
      whereArgs: [call.id.toString()],
    );
    return result.isNotEmpty;
  } catch (e) {
    return false;
  }
}

Future<void> _markCallProcessed(CallLogEntry call) async {
  final db = await DatabaseService.db;
  await db.insert('processed_calls', {
    'call_id': call.id.toString(),
    'phone': call.number,
    'timestamp': call.timestamp,
    'call_type': call.callType?.index,
    'processed_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _processNewCall(CallLogEntry call) async {
  String callType = 'unknown';
  if (call.callType == CallType.incoming) callType = 'incoming';
  if (call.callType == CallType.outgoing) callType = 'outgoing';
  if (call.callType == CallType.missed) callType = 'missed';

  final db = await DatabaseService.db;

  // Save lead
  try {
    final existing = await db.query(
      'leads',
      where: 'phone = ? AND type = ? AND timestamp = ?',
      whereArgs: [call.number, callType, call.timestamp],
    );
    if (existing.isEmpty) {
      await db.insert('leads', {
        'phone': call.number,
        'type': callType,
        'timestamp': call.timestamp ?? DateTime.now().millisecondsSinceEpoch,
        'source': 'auto_detected',
        'blocked': 0,
        'count': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  } catch (e) {
    print('❌ Failed to save lead: $e');
  }

  await NotificationService().notifyCallDetected(call.number!, callType);

  // ✅ Dedup check — don't send if already sent today for this call type
  final alreadySent = await _wasAnySmsAlreadySent(call.number!, callType);
  if (alreadySent) {
    print(
      '⏭️ SMS already sent to ${call.number} for $callType today — skipping',
    );
    return;
  }

  await _triggerAutoSmsRules(call.number!, callType);
}

Future<bool> _wasAnySmsAlreadySent(String phone, String callType) async {
  try {
    final db = await DatabaseService.db;
    final result = await db.query(
      'sms_sent_log',
      where: 'phone = ? AND call_type = ?',
      whereArgs: [phone, callType],
    );
    return result.isNotEmpty;
  } catch (e) {
    return false;
  }
}

// ─── Auto SMS rules ───────────────────────────────────────────────

Future<void> _triggerAutoSmsRules(String phone, String callType) async {
  final db = await DatabaseService.db;

  try {
    final rules = await db.query(
      'auto_sms_rules',
      where: 'trigger_type = ? AND is_active = 1',
      whereArgs: [callType],
    );

    if (rules.isEmpty) return;

    for (var rule in rules) {
      final templateId = rule['template_id'] as int?;
      final customMessage = rule['custom_message'] as String?;
      final delayMinutes = rule['delay_minutes'] as int? ?? 0;
      final ruleId = rule['id'] as int?;

      if (ruleId == null) continue;

      // ✅ Per-rule dedup check
      final alreadySentForRule = await _wasSmsSentForRule(phone, ruleId);
      if (alreadySentForRule) {
        print('⏭️ SMS already sent for rule $ruleId to $phone, skipping');
        continue;
      }

      String message = '';
      if (customMessage != null && customMessage.isNotEmpty) {
        message = customMessage;
      } else if (templateId != null) {
        final templates = await db.query(
          'templates',
          where: 'id = ?',
          whereArgs: [templateId],
        );
        if (templates.isEmpty) continue;
        message = templates.first['message'] as String? ?? '';
      }

      if (message.isEmpty) {
        print('⚠️ No message found for rule ${rule['name']}, skipping');
        continue;
      }

      if (delayMinutes == 0) {
        await _sendSmsNow(phone, message);
        await _logAutoSms(phone, message, callType, ruleId);
        await _markSmsSent(phone, ruleId, callType);
      } else {
        // ✅ Check if already scheduled
        final alreadyScheduled = await db.query(
          'scheduled_sms',
          where: 'phone = ? AND rule_id = ? AND status = "pending"',
          whereArgs: [phone, ruleId],
        );
        if (alreadyScheduled.isNotEmpty) continue;

        await db.insert('scheduled_sms', {
          'phone': phone,
          'message': message,
          'rule_id': ruleId,
          'call_type': callType,
          'scheduled_at': DateTime.now().millisecondsSinceEpoch,
          'send_at': DateTime.now()
              .add(Duration(minutes: delayMinutes))
              .millisecondsSinceEpoch,
          'status': 'pending',
        });
        await _markSmsSent(phone, ruleId, callType);
        print('⏰ SMS scheduled for ${delayMinutes}min to $phone');
      }
    }
  } catch (e) {
    print('❌ Error triggering rules: $e');
  }
}

Future<bool> _wasSmsSentForRule(String phone, int ruleId) async {
  try {
    final db = await DatabaseService.db;
    final result = await db.query(
      'sms_sent_log',
      where: 'phone = ? AND rule_id = ?',
      whereArgs: [phone, ruleId],
    );
    return result.isNotEmpty;
  } catch (e) {
    return false;
  }
}

Future<void> _markSmsSent(String phone, int ruleId, String callType) async {
  try {
    final db = await DatabaseService.db;
    await db.insert('sms_sent_log', {
      'phone': phone,
      'rule_id': ruleId,
      'call_type': callType,
      'sent_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  } catch (e) {
    print('⚠️ Could not mark SMS sent: $e');
  }
}

// ─── SMS sending ──────────────────────────────────────────────────

Future<void> _sendSmsNow(String phone, String message) async {
  try {
    final telephony = Telephony.instance;
    await telephony.sendSms(to: phone, message: message);
    print('📤 SMS sent to $phone');
  } catch (e) {
    print('❌ SMS failed to $phone: $e');
    // ✅ Fallback — queue as scheduled so it retries
    try {
      final db = await DatabaseService.db;
      await db.insert('scheduled_sms', {
        'phone': phone,
        'message': message,
        'rule_id': null,
        'call_type': 'retry',
        'scheduled_at': DateTime.now().millisecondsSinceEpoch,
        'send_at': DateTime.now()
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
        'status': 'pending',
      });
      print('🔄 Queued SMS for retry in 2 minutes');
    } catch (_) {}
  }
}

Future<void> _processPendingScheduledSms() async {
  final db = await DatabaseService.db;
  final now = DateTime.now().millisecondsSinceEpoch;

  try {
    final pending = await db.query(
      'scheduled_sms',
      where: "status = 'pending' AND send_at <= ?",
      whereArgs: [now],
    );

    if (pending.isEmpty) return;

    print('⏰ Sending ${pending.length} scheduled SMS...');

    for (var sms in pending) {
      final phone = sms['phone'] as String?;
      final message = sms['message'] as String?;
      final smsId = sms['id'] as int?;
      if (phone == null || message == null) continue;

      try {
        final telephony = Telephony.instance;
        await telephony.sendSms(to: phone, message: message);
        if (smsId != null) {
          await db.update(
            'scheduled_sms',
            {'status': 'sent', 'sent_at': now},
            where: 'id = ?',
            whereArgs: [smsId],
          );
        }
        print('✅ Sent scheduled SMS to $phone');
      } catch (e) {
        if (smsId != null) {
          await db.update(
            'scheduled_sms',
            {'status': 'failed', 'error': e.toString()},
            where: 'id = ?',
            whereArgs: [smsId],
          );
        }
        print('❌ Failed scheduled SMS to $phone: $e');
      }
    }
  } catch (e) {
    print('❌ Error processing scheduled SMS: $e');
  }
}

Future<void> _logAutoSms(
  String phone,
  String message,
  String callType,
  int? ruleId,
) async {
  final db = await DatabaseService.db;
  try {
    await db.insert('auto_sms_logs', {
      'phone': phone,
      'message': message,
      'call_type': callType,
      'rule_id': ruleId,
      'sent_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'sent',
    });
  } catch (e) {
    print('❌ Failed to log SMS: $e');
  }
}

// ─── Service manager ──────────────────────────────────────────────

class BackgroundServiceManager {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'auto_sms_channel',
        initialNotificationTitle: 'Auto SMS Active',
        initialNotificationContent: 'Monitoring calls for auto-replies',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onBackgroundServiceStart,
      ),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
  }

  static Future<bool> isRunning() async {
    return await FlutterBackgroundService().isRunning();
  }

  // ✅ Call this whenever rules are saved or updated
  static Future<void> syncRulesToNative({bool? enabled}) async {
    await _syncRulesToNative(enabled: enabled);
  }
}
