import 'dart:async';
import 'dart:ui';

import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ✅ Single background isolate entry point
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // ✅ Listen for native SMS sent event (from Kotlin layer)
  const nativeChannel = MethodChannel('com.nextracom.smartpinger/native_events');
  nativeChannel.setMethodCallHandler((call) async {
    if (call.method == 'smsSentByNative') {
      final args = call.arguments as Map;
      final phone    = args['phone']     as String?;
      final callType = args['call_type'] as String?;
      final message  = args['message']   as String?;
      if (phone != null && message != null && callType != null) {
        // ✅ Open its own DB connection — isolate-safe
        await _logAutoSmsIsolated(phone, message, callType, null);
      }
    }
  });

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }
  service.on('stop').listen((_) => service.stopSelf());

  // Sync rules to native on start
  await _syncRulesToNative();

  // ✅ Poll every 10 seconds
  Timer.periodic(const Duration(seconds: 10), (_) async {
    await _checkForNewCalls();
  });

  // Process scheduled SMS every 30 seconds
  Timer.periodic(const Duration(seconds: 30), (_) async {
    await _processPendingScheduledSms();
  });

  // Daily cleanup
  Timer.periodic(const Duration(hours: 24), (_) async {
    await _cleanDailySmsLog();
    await _syncRulesToNative();
  });

  // Update notification every minute
  Timer.periodic(const Duration(minutes: 1), (_) async {
    if (service is AndroidServiceInstance) {
      final now = DateTime.now();
      service.setForegroundNotificationInfo(
        title: 'Smart Pinger Active',
        content: 'Auto SMS running • ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      );
    }
  });
}

// ── Isolate-safe DB helper ────────────────────────────────────────
// ✅ Opens a fresh DB connection per call in background isolate
// Avoids multi-isolate SQLite conflict
Future<T> _withDb<T>(Future<T> Function(Database db) fn) async {
  final db = await DatabaseService.db;
  return fn(db);
}

// ── Native sync ───────────────────────────────────────────────────
Future<void> _syncRulesToNative({bool? enabled}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = enabled ?? prefs.getBool('auto_trigger_enabled') ?? false;

    await _withDb((db) async {
      for (final callType in ['missed', 'incoming', 'outgoing']) {
        final rules = await db.query('auto_sms_rules',
          where: 'trigger_type = ? AND is_active = 1',
          whereArgs: [callType], limit: 1, orderBy: 'created_at DESC');

        if (rules.isEmpty) {
          await prefs.remove('auto_sms_message_$callType');
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
            final templates = await db.query('templates',
              where: 'id = ?', whereArgs: [templateId]);
            if (templates.isNotEmpty) {
              message = templates.first['message'] as String? ?? '';
            }
          }
        }

        if (message.isNotEmpty) {
          await prefs.setString('auto_sms_message_$callType', message);
        } else {
          await prefs.remove('auto_sms_message_$callType');
        }
      }
    });

    await prefs.setBool('auto_trigger_enabled', isEnabled);
  } catch (e) {
    debugPrint('❌ syncRulesToNative error: $e');
  }
}

// ── Daily cleanup ─────────────────────────────────────────────────
Future<void> _cleanDailySmsLog() async {
  try {
    final yesterday = DateTime.now()
        .subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    await _withDb((db) => db.delete('sms_sent_log',
      where: 'sent_at < ?', whereArgs: [yesterday]));

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _getTodayKey();
    for (final key in prefs.getKeys().where((k) => k.startsWith('sent_'))) {
      if (!key.contains(todayKey)) await prefs.remove(key);
    }
  } catch (e) {
    debugPrint('❌ cleanDailySmsLog error: $e');
  }
}

String _getTodayKey() {
  final now = DateTime.now();
  return '${now.year}_${now.month}_${now.day}';
}

// ── Call checking ─────────────────────────────────────────────────
Future<void> _checkForNewCalls() async {
  try {
    final fiveMinutesAgo = DateTime.now()
        .subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;

    final allLogs  = await CallLog.get();
    final recent   = allLogs.where((c) =>
      c.timestamp != null && c.timestamp! >= fiveMinutesAgo).toList();

    if (recent.isEmpty) return;

    for (final call in recent) {
      if (call.number == null || call.number!.isEmpty) continue;
      if (call.timestamp == null) continue;

      final processed = await _isCallProcessed(call);
      if (!processed) {
        await _processNewCall(call);
        await _markCallProcessed(call);
      }
    }
  } catch (e) {
    debugPrint('❌ checkForNewCalls error: $e');
  }
}

Future<bool> _isCallProcessed(CallLogEntry call) async {
  try {
    return await _withDb((db) async {
      final r = await db.query('processed_calls',
        where: 'call_id = ?', whereArgs: [call.id.toString()]);
      return r.isNotEmpty;
    });
  } catch (_) { return false; }
}

Future<void> _markCallProcessed(CallLogEntry call) async {
  try {
    await _withDb((db) => db.insert('processed_calls', {
      'call_id':    call.id.toString(),
      'phone':      call.number,
      'timestamp':  call.timestamp,
      'call_type':  call.callType?.index,
      'processed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace));
  } catch (e) {
    debugPrint('❌ markCallProcessed error: $e');
  }
}

Future<void> _processNewCall(CallLogEntry call) async {
  String callType = 'unknown';
  if (call.callType == CallType.incoming) callType = 'incoming';
  if (call.callType == CallType.outgoing) callType = 'outgoing';
  if (call.callType == CallType.missed)   callType = 'missed';

  // Save lead
  try {
    await _withDb((db) => db.insert('leads', {
      'phone':     call.number,
      'type':      callType,
      'timestamp': call.timestamp ?? DateTime.now().millisecondsSinceEpoch,
      'source':    'auto_detected',
      'blocked':   0,
      'count':     1,
    }, conflictAlgorithm: ConflictAlgorithm.replace));
  } catch (e) {
    debugPrint('❌ save lead error: $e');
  }

  await NotificationService().notifyCallDetected(call.number!, callType);

  // Dedup check
  final alreadySent = await _wasAnySmsAlreadySent(call.number!, callType);
  if (alreadySent) return;

  await _triggerAutoSmsRules(call.number!, callType);
}

Future<bool> _wasAnySmsAlreadySent(String phone, String callType) async {
  try {
    return await _withDb((db) async {
      final r = await db.query('sms_sent_log',
        where: 'phone = ? AND call_type = ?', whereArgs: [phone, callType]);
      return r.isNotEmpty;
    });
  } catch (_) { return false; }
}

// ── Auto SMS rules ────────────────────────────────────────────────
Future<void> _triggerAutoSmsRules(String phone, String callType) async {
  try {
    final rules = await _withDb((db) => db.query('auto_sms_rules',
      where: 'trigger_type = ? AND is_active = 1', whereArgs: [callType]));

    if (rules.isEmpty) return;

    for (final rule in rules) {
      final ruleId       = rule['id'] as int?;
      final templateId   = rule['template_id'] as int?;
      final customMsg    = rule['custom_message'] as String?;
      final delayMinutes = rule['delay_minutes'] as int? ?? 0;
      if (ruleId == null) continue;

      final alreadySent = await _wasSmsSentForRule(phone, ruleId);
      if (alreadySent) continue;

      // Get message
      String message = '';
      if (customMsg != null && customMsg.isNotEmpty) {
        message = customMsg;
      } else if (templateId != null) {
        final templates = await _withDb((db) => db.query('templates',
          where: 'id = ?', whereArgs: [templateId]));
        if (templates.isEmpty) continue;
        message = templates.first['message'] as String? ?? '';
      }
      if (message.isEmpty) continue;

      if (delayMinutes == 0) {
        await _sendSmsViaNative(phone, message);
        await _logAutoSmsIsolated(phone, message, callType, ruleId);
        await _markSmsSent(phone, ruleId, callType);
      } else {
        final existing = await _withDb((db) => db.query('scheduled_sms',
          where: 'phone = ? AND rule_id = ? AND status = "pending"',
          whereArgs: [phone, ruleId]));
        if (existing.isNotEmpty) continue;

        await _withDb((db) => db.insert('scheduled_sms', {
          'phone':        phone,
          'message':      message,
          'rule_id':      ruleId,
          'call_type':    callType,
          'scheduled_at': DateTime.now().millisecondsSinceEpoch,
          'send_at':      DateTime.now()
              .add(Duration(minutes: delayMinutes)).millisecondsSinceEpoch,
          'status':       'pending',
        }));
        await _markSmsSent(phone, ruleId, callType);
      }
    }
  } catch (e) {
    debugPrint('❌ triggerAutoSmsRules error: $e');
  }
}

Future<bool> _wasSmsSentForRule(String phone, int ruleId) async {
  try {
    return await _withDb((db) async {
      final r = await db.query('sms_sent_log',
        where: 'phone = ? AND rule_id = ?', whereArgs: [phone, ruleId]);
      return r.isNotEmpty;
    });
  } catch (_) { return false; }
}

Future<void> _markSmsSent(String phone, int ruleId, String callType) async {
  try {
    await _withDb((db) => db.insert('sms_sent_log', {
      'phone':     phone,
      'rule_id':   ruleId,
      'call_type': callType,
      'sent_at':   DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore));
  } catch (e) {
    debugPrint('⚠️ markSmsSent error: $e');
  }
}

// ── SMS sending ───────────────────────────────────────────────────
// ✅ Use native Kotlin SMS only — removed another_telephony
// Routes through the native SmsManager via MethodChannel
Future<void> _sendSmsViaNative(String phone, String message) async {
  try {
    const channel = MethodChannel('com.nextracom.smartpinger/settings');
    await channel.invokeMethod('sendSms', {
      'phone':   phone,
      'message': message,
    });
    debugPrint('📤 SMS sent to $phone via native');
  } catch (e) {
    debugPrint('❌ Native SMS failed to $phone: $e');
    // Queue for retry
    try {
      await _withDb((db) => db.insert('scheduled_sms', {
        'phone':        phone,
        'message':      message,
        'rule_id':      null,
        'call_type':    'retry',
        'scheduled_at': DateTime.now().millisecondsSinceEpoch,
        'send_at':      DateTime.now()
            .add(const Duration(minutes: 2)).millisecondsSinceEpoch,
        'status':       'pending',
      }));
    } catch (_) {}
  }
}

// ── Scheduled SMS ─────────────────────────────────────────────────
Future<void> _processPendingScheduledSms() async {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = await _withDb((db) => db.query('scheduled_sms',
      where: "status = 'pending' AND send_at <= ?", whereArgs: [now]));

    for (final sms in pending) {
      final phone   = sms['phone']   as String?;
      final message = sms['message'] as String?;
      final smsId   = sms['id']      as int?;
      if (phone == null || message == null) continue;

      try {
        await _sendSmsViaNative(phone, message);
        if (smsId != null) {
          await _withDb((db) => db.update('scheduled_sms',
            {'status': 'sent', 'sent_at': now},
            where: 'id = ?', whereArgs: [smsId]));
        }
      } catch (e) {
        if (smsId != null) {
          await _withDb((db) => db.update('scheduled_sms',
            {'status': 'failed', 'error': e.toString()},
            where: 'id = ?', whereArgs: [smsId]));
        }
      }
    }
  } catch (e) {
    debugPrint('❌ processPendingScheduledSms error: $e');
  }
}

// ── SMS log ───────────────────────────────────────────────────────
Future<void> _logAutoSmsIsolated(
    String phone, String message, String callType, int? ruleId) async {
  try {
    await _withDb((db) => db.insert('auto_sms_logs', {
      'phone':     phone,
      'message':   message,
      'call_type': callType,
      'rule_id':   ruleId,
      'sent_at':   DateTime.now().millisecondsSinceEpoch,
      'status':    'sent',
    }));
  } catch (e) {
    debugPrint('❌ logAutoSms error: $e');
  }
}

// ── Service manager ───────────────────────────────────────────────
class BackgroundServiceManager {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'auto_sms_channel',
        initialNotificationTitle: 'Smart Pinger Active',
        initialNotificationContent: 'Monitoring calls for auto SMS',
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
    if (!await service.isRunning()) await service.startService();
  }

  static Future<void> stop() async {
    FlutterBackgroundService().invoke('stop');
  }

  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }

  static Future<void> syncRulesToNative({bool? enabled}) async {
    await _syncRulesToNative(enabled: enabled);
  }
}
