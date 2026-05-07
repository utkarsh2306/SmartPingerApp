import 'dart:async';
import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/notification_service.dart';
import 'package:message_me/service/sms_service.dart';
import 'package:sqflite/sqflite.dart';

class CallListenerService {
  static Timer? _pollingTimer;
  static bool _isRunning = false;

  static void startListening() {
    if (_isRunning) {
      debugPrint('Call listener already running');
      return;
    }
    _isRunning = true;
    debugPrint('🔵 Call listener service STARTED');
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkForNewCalls();
    });
  }

  static void stopListening() {
    _pollingTimer?.cancel();
    _isRunning = false;
    debugPrint('🔴 Call listener service STOPPED');
  }

  static bool isRunning() => _isRunning;

  // ── Call checking ────────────────────────────────────────────────

  static Future<void> _checkForNewCalls() async {
    try {
      final allLogs = await CallLog.get();
      final fiveMinutesAgo = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch;

      final recentCalls = allLogs.where((call) {
        return call.timestamp != null && call.timestamp! >= fiveMinutesAgo;
      }).toList();

      if (recentCalls.isEmpty) return;

      debugPrint('📞 Checking ${recentCalls.length} recent calls...');

      for (var call in recentCalls) {
        if (call.number == null || call.number!.isEmpty) continue;
        if (call.timestamp == null) continue;

        final isProcessed = await _isCallProcessed(call);
        if (!isProcessed) {
          debugPrint('✅ New call: ${call.number} (${call.callType})');
          await _processNewCall(call);
          await _markCallProcessed(call);
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking calls: $e');
    }
  }

  static Future<bool> _isCallProcessed(CallLogEntry call) async {
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

  static Future<void> _markCallProcessed(CallLogEntry call) async {
    final db = await DatabaseService.db;
    await db.insert('processed_calls', {
      'call_id': call.id.toString(),
      'phone': call.number,
      'timestamp': call.timestamp,
      'call_type': call.callType?.index,
      'processed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint('💾 Marked call processed: ${call.number}');
  }

  static Future<void> _processNewCall(CallLogEntry call) async {
    debugPrint('🔄 Processing: ${call.number}');

    String callType = 'unknown';
    if (call.callType == CallType.incoming) callType = 'incoming';
    if (call.callType == CallType.outgoing) callType = 'outgoing';
    if (call.callType == CallType.missed) callType = 'missed';

    final db = await DatabaseService.db;

    // ✅ Save lead regardless (each call is a valid lead entry)
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
        debugPrint('💾 Saved lead: ${call.number}');
      }
    } catch (e) {
      debugPrint('❌ Failed to save lead: $e');
    }

    // ✅ Always notify about the call
    await NotificationService().notifyCallDetected(call.number!, callType);

    // ✅ But only trigger SMS rules if not already sent today
    final alreadySentForAnyRule = await _wasAnySmsAlreadySent(
      call.number!,
      callType,
    );
    if (alreadySentForAnyRule) {
      debugPrint(
        '⏭️ SMS already sent to ${call.number} for $callType today — skipping rules',
      );
      return;
    }

    await _triggerAutoSmsRules(call.number!, callType);
  }
  // ── SMS rules ────────────────────────────────────────────────────

  static Future<void> _triggerAutoSmsRules(
    String phone,
    String callType,
  ) async {
    final db = await DatabaseService.db;

    try {
      final rules = await db.query(
        'auto_sms_rules',
        where: 'trigger_type = ? AND is_active = 1',
        whereArgs: [callType],
      );

      if (rules.isEmpty) return;

      debugPrint('📋 ${rules.length} rule(s) found for $callType');

      for (var rule in rules) {
        final templateId = rule['template_id'] as int?;
        final customMessage = rule['custom_message'] as String?;
        final delayMinutes = rule['delay_minutes'] as int? ?? 0;
        final ruleId = rule['id'] as int?;
        final ruleName = rule['name'] as String? ?? 'Unnamed';

        if (ruleId == null) continue;

        // ✅ Skip if SMS already sent to this number for this rule
        final alreadySent = await _wasSmsSentAlready(phone, ruleId);
        if (alreadySent) {
          debugPrint(
            '⏭️ SMS already sent to $phone for rule "$ruleName", skipping',
          );
          continue;
        }

        // Determine message
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
          debugPrint('⚠️ No message for rule "$ruleName", skipping');
          continue;
        }

        if (delayMinutes == 0) {
          debugPrint('📤 Sending SMS immediately to $phone...');
          await SmsService.send(phone, message);
          await _logAutoSms(phone, message, callType, ruleId);
          // ✅ Mark as sent — prevents future calls triggering this rule again
          await _markSmsSent(phone, ruleId, callType);
        } else {
          // ✅ Check if already scheduled for this phone + rule
          final alreadyScheduled = await db.query(
            'scheduled_sms',
            where: 'phone = ? AND rule_id = ? AND status = "pending"',
            whereArgs: [phone, ruleId],
          );

          if (alreadyScheduled.isNotEmpty) {
            debugPrint('⏭️ SMS already scheduled for $phone rule "$ruleName"');
            continue;
          }

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

          // ✅ Mark as sent immediately so repeat calls don't queue another
          await _markSmsSent(phone, ruleId, callType);
          debugPrint('⏰ Scheduled SMS to $phone in ${delayMinutes}min');
        }
      }
    } catch (e) {
      debugPrint('❌ Error triggering rules: $e');
    }
  }

  /// Returns true if ANY SMS was sent to this phone for this call type today
  static Future<bool> _wasAnySmsAlreadySent(
    String phone,
    String callType,
  ) async {
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
  // ── Duplicate prevention helpers ─────────────────────────────────

  /// Returns true if an SMS was already sent/scheduled for this phone + rule
  static Future<bool> _wasSmsSentAlready(String phone, int ruleId) async {
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

  /// Records that an SMS was sent/scheduled for this phone + rule
  static Future<void> _markSmsSent(
    String phone,
    int ruleId,
    String callType,
  ) async {
    try {
      final db = await DatabaseService.db;
      await db.insert('sms_sent_log', {
        'phone': phone,
        'rule_id': ruleId,
        'call_type': callType,
        'sent_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      debugPrint('📝 Marked SMS sent: $phone / rule $ruleId / $callType');
    } catch (e) {
      debugPrint('⚠️ Could not mark SMS sent: $e');
    }
  }

  /// Cleans log entries older than 24 hours so numbers can receive SMS again next day
  static Future<void> cleanDailySmsLog() async {
    final db = await DatabaseService.db;
    final yesterday = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final deleted = await db.delete(
      'sms_sent_log',
      where: 'sent_at < ?',
      whereArgs: [yesterday],
    );
    if (deleted > 0) {
      debugPrint('🧹 Cleaned $deleted old sms_sent_log entries');
    }
  }

  // ── Logging and scheduling ───────────────────────────────────────

  static Future<void> _logAutoSms(
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
      debugPrint('❌ Failed to log SMS: $e');
    }
  }

  static Future<void> processPendingScheduledSms() async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final pending = await db.query(
        'scheduled_sms',
        where: "status = 'pending' AND send_at <= ?",
        whereArgs: [now],
      );

      if (pending.isEmpty) return;

      debugPrint('⏰ Processing ${pending.length} scheduled SMS...');

      for (var sms in pending) {
        final phone = sms['phone'] as String?;
        final message = sms['message'] as String?;
        final smsId = sms['id'] as int?;

        if (phone == null || message == null) continue;

        try {
          await SmsService.send(phone, message);
          if (smsId != null) {
            await db.update(
              'scheduled_sms',
              {'status': 'sent', 'sent_at': now},
              where: 'id = ?',
              whereArgs: [smsId],
            );
          }
          debugPrint('✅ Sent scheduled SMS to $phone');
        } catch (e) {
          if (smsId != null) {
            await db.update(
              'scheduled_sms',
              {'status': 'failed', 'error': e.toString()},
              where: 'id = ?',
              whereArgs: [smsId],
            );
          }
          debugPrint('❌ Failed scheduled SMS to $phone: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error processing scheduled SMS: $e');
    }
  }

  static Future<void> cleanOldProcessedCalls() async {
    final db = await DatabaseService.db;
    final daysAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    await db.delete(
      'processed_calls',
      where: 'processed_at < ?',
      whereArgs: [daysAgo],
    );
  }
}
