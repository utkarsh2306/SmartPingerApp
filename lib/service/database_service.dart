import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;
  static const int _version = 8;

  // ✅ Isolate-safe: returns cached instance in main isolate,
  // opens fresh connection in background isolates
  static Future<Database> get db async {
    // In background isolate _db is always null (different memory space)
    // so this always opens fresh — which is correct for isolate safety
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'leads.db');

    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        // Leads table
        await db.execute('''
          CREATE TABLE leads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT,
            name TEXT,
            type TEXT,
            timestamp INTEGER,
            blocked INTEGER DEFAULT 0,
            last_contacted INTEGER,
            count INTEGER DEFAULT 1,
            source TEXT DEFAULT 'call_log',
            message_sent INTEGER DEFAULT 0,
            message_status TEXT,
            message_timestamp INTEGER,
            message_type TEXT,
            message_error TEXT
          )
        ''');

        // Templates table
        await db.execute('''
          CREATE TABLE templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            message TEXT,
            category TEXT DEFAULT 'general',
            created_at INTEGER,
            usage_count INTEGER DEFAULT 0,
            is_default INTEGER DEFAULT 0
          )
        ''');

        // Blocked numbers table
        await db.execute('''
          CREATE TABLE blocked_numbers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT UNIQUE,
            reason TEXT,
            blocked_at INTEGER
          )
        ''');

        // Auto SMS rules table
        await db.execute('''
          CREATE TABLE auto_sms_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            trigger_type TEXT,
            delay_minutes INTEGER DEFAULT 0,
            template_id INTEGER,
            custom_message TEXT,
            is_active INTEGER DEFAULT 1,
            created_at INTEGER
          )
        ''');

        // Processed calls table
        await db.execute('''
          CREATE TABLE processed_calls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            call_id TEXT UNIQUE,
            phone TEXT,
            timestamp INTEGER,
            call_type INTEGER,
            processed_at INTEGER
          )
        ''');

        // Scheduled SMS table
        await db.execute('''
          CREATE TABLE scheduled_sms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT,
            message TEXT,
            rule_id INTEGER,
            call_type TEXT,
            scheduled_at INTEGER,
            send_at INTEGER,
            sent_at INTEGER,
            status TEXT,
            error TEXT
          )
        ''');

        // Auto SMS logs table
        await db.execute('''
          CREATE TABLE auto_sms_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT,
            message TEXT,
            call_type TEXT,
            rule_id INTEGER,
            sent_at INTEGER,
            status TEXT
          )
        ''');

        // App notifications table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            type TEXT NOT NULL,
            related_id TEXT,
            timestamp INTEGER NOT NULL,
            is_read INTEGER DEFAULT 0
          )
        ''');

        // ✅ SMS sent log — prevents duplicate SMS per phone per rule
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sms_sent_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT NOT NULL,
            rule_id INTEGER NOT NULL,
            call_type TEXT NOT NULL,
            sent_at INTEGER NOT NULL,
            UNIQUE(phone, rule_id)
          )
        ''');

        // Indexes
        await db.execute('CREATE INDEX idx_leads_phone ON leads(phone)');
        await db.execute(
          'CREATE INDEX idx_leads_timestamp ON leads(timestamp)',
        );
        await db.execute('CREATE INDEX idx_leads_type ON leads(type)');
        await db.execute(
          'CREATE INDEX idx_leads_message_sent ON leads(message_sent)',
        );
        await db.execute(
          'CREATE INDEX idx_processed_calls_call_id ON processed_calls(call_id)',
        );
        await db.execute(
          'CREATE INDEX idx_scheduled_sms_send_at ON scheduled_sms(send_at)',
        );
        await db.execute(
          'CREATE INDEX idx_scheduled_sms_status ON scheduled_sms(status)',
        );
        await db.execute(
          'CREATE INDEX idx_sms_sent_log_phone ON sms_sent_log(phone)',
        );
        await db.execute(
          'CREATE INDEX idx_sms_sent_log_rule ON sms_sent_log(rule_id)',
        );

        await _insertDefaultTemplates(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint('🔄 Upgrading DB from v$oldVersion to v$newVersion');

        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE leads ADD COLUMN name TEXT');
            await db.execute(
              'ALTER TABLE leads ADD COLUMN last_contacted INTEGER',
            );
            await db.execute(
              'ALTER TABLE leads ADD COLUMN count INTEGER DEFAULT 1',
            );
            await db.execute(
              'ALTER TABLE leads ADD COLUMN source TEXT DEFAULT "call_log"',
            );
            await db.execute(
              'ALTER TABLE templates ADD COLUMN category TEXT DEFAULT "general"',
            );
            await db.execute(
              'ALTER TABLE templates ADD COLUMN created_at INTEGER',
            );
            await db.execute(
              'ALTER TABLE templates ADD COLUMN usage_count INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE templates ADD COLUMN is_default INTEGER DEFAULT 0',
            );
            debugPrint('✅ Upgraded to v2');
          } catch (e) {
            debugPrint('⚠️ v2 upgrade error: $e');
          }
        }

        if (oldVersion < 3) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS processed_calls (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                call_id TEXT UNIQUE,
                phone TEXT,
                timestamp INTEGER,
                call_type INTEGER,
                processed_at INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS scheduled_sms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                phone TEXT,
                message TEXT,
                rule_id INTEGER,
                call_type TEXT,
                scheduled_at INTEGER,
                send_at INTEGER,
                sent_at INTEGER,
                status TEXT,
                error TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS auto_sms_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                phone TEXT,
                message TEXT,
                call_type TEXT,
                rule_id INTEGER,
                sent_at INTEGER,
                status TEXT
              )
            ''');
            debugPrint('✅ Upgraded to v3');
          } catch (e) {
            debugPrint('⚠️ v3 upgrade error: $e');
          }
        }

        if (oldVersion < 4) {
          try {
            final cols = await db.rawQuery('PRAGMA table_info(leads)');
            final names = cols.map((c) => c['name'] as String).toList();

            if (!names.contains('message_sent')) {
              await db.execute(
                'ALTER TABLE leads ADD COLUMN message_sent INTEGER DEFAULT 0',
              );
            }
            if (!names.contains('message_status')) {
              await db.execute(
                'ALTER TABLE leads ADD COLUMN message_status TEXT',
              );
            }
            if (!names.contains('message_timestamp')) {
              await db.execute(
                'ALTER TABLE leads ADD COLUMN message_timestamp INTEGER',
              );
            }
            if (!names.contains('message_type')) {
              await db.execute(
                'ALTER TABLE leads ADD COLUMN message_type TEXT',
              );
            }
            if (!names.contains('message_error')) {
              await db.execute(
                'ALTER TABLE leads ADD COLUMN message_error TEXT',
              );
            }
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_leads_message_sent ON leads(message_sent)',
            );
            debugPrint('✅ Upgraded to v4');
          } catch (e) {
            debugPrint('⚠️ v4 upgrade error: $e');
          }
        }

        if (oldVersion < 7) {
          try {
            final cols = await db.rawQuery('PRAGMA table_info(auto_sms_rules)');
            final names = cols.map((c) => c['name'] as String).toList();
            if (!names.contains('custom_message')) {
              await db.execute(
                'ALTER TABLE auto_sms_rules ADD COLUMN custom_message TEXT',
              );
              debugPrint('✅ Added custom_message column');
            }
            debugPrint('✅ Upgraded to v7');
          } catch (e) {
            debugPrint('⚠️ v7 upgrade error: $e');
          }
        }

        // ✅ Version 8 — add sms_sent_log table
        if (oldVersion < 8) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sms_sent_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                phone TEXT NOT NULL,
                rule_id INTEGER NOT NULL,
                call_type TEXT NOT NULL,
                sent_at INTEGER NOT NULL,
                UNIQUE(phone, rule_id)
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sms_sent_log_phone ON sms_sent_log(phone)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sms_sent_log_rule ON sms_sent_log(rule_id)',
            );
            debugPrint('✅ Upgraded to v8 — sms_sent_log created');
          } catch (e) {
            debugPrint('⚠️ v8 upgrade error: $e');
          }
        }
      },
    );
  }

  static Future<void> _insertDefaultTemplates(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM templates'),
        ) ??
        0;

    if (count == 0) {
      await db.insert('templates', {
        'title': 'Follow-up Message',
        'message':
            'Hello, this is a follow-up message from SMS Marketing. Thank you for your time!',
        'category': 'follow_up',
        'created_at': now,
        'usage_count': 0,
        'is_default': 1,
      });
      await db.insert('templates', {
        'title': 'Appointment Reminder',
        'message':
            'Reminder: You have an upcoming appointment. Please confirm your availability.',
        'category': 'reminder',
        'created_at': now,
        'usage_count': 0,
        'is_default': 1,
      });
      await db.insert('templates', {
        'title': 'Thank You',
        'message': 'Thank you for your time! We appreciate your business.',
        'category': 'thanks',
        'created_at': now,
        'usage_count': 0,
        'is_default': 1,
      });
      await db.insert('templates', {
        'title': 'Missed Call Alert',
        'message':
            'Sorry we missed your call. Please contact us at your convenience.',
        'category': 'missed_call',
        'created_at': now,
        'usage_count': 0,
        'is_default': 1,
      });
      debugPrint('✅ Default templates inserted');
    }
  }

  // ── Helper methods ───────────────────────────────────────────────

  static Future<void> updateMessageStatus({
    required int leadId,
    required bool sent,
    String? status,
    String? messageType,
    String? error,
  }) async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'leads',
      {
        'message_sent': sent ? 1 : 0,
        'message_status': status,
        'message_timestamp': now,
        'message_type': messageType,
        'message_error': error,
        if (sent) 'last_contacted': now,
      },
      where: 'id = ?',
      whereArgs: [leadId],
    );
  }

  static Future<List<Map<String, dynamic>>> getLeadsWithMessageStatus({
    String? type,
    bool? messageSent,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final db = await DatabaseService.db;
    String where = '1=1';
    List<dynamic> args = [];

    if (type != null) {
      where += ' AND type = ?';
      args.add(type);
    }
    if (messageSent != null) {
      where += ' AND message_sent = ?';
      args.add(messageSent ? 1 : 0);
    }
    if (fromDate != null) {
      where += ' AND timestamp >= ?';
      args.add(fromDate.millisecondsSinceEpoch);
    }
    if (toDate != null) {
      where += ' AND timestamp <= ?';
      args.add(toDate.millisecondsSinceEpoch);
    }

    return await db.query(
      'leads',
      where: where,
      whereArgs: args,
      orderBy: 'timestamp DESC',
    );
  }

  static Future<Map<String, dynamic>> getMessageStatistics() async {
    final db = await DatabaseService.db;

    final totalLeads =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) as count FROM leads'),
        ) ??
        0;
    final messagesSent =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) as count FROM leads WHERE message_sent = 1',
          ),
        ) ??
        0;
    final messagesFailed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) as count FROM leads WHERE message_status = "failed"',
          ),
        ) ??
        0;

    final sevenDaysAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    final recentMessages =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) as count FROM leads WHERE message_sent = 1 AND message_timestamp >= ?',
            [sevenDaysAgo],
          ),
        ) ??
        0;

    return {
      'totalLeads': totalLeads,
      'messagesSent': messagesSent,
      'messagesFailed': messagesFailed,
      'recentMessages': recentMessages,
      'conversionRate': totalLeads > 0
          ? ((messagesSent / totalLeads) * 100).toStringAsFixed(1)
          : '0',
    };
  }

  static Future<bool> doTemplatesExist() async {
    final db = await DatabaseService.db;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) as count FROM templates'),
        ) ??
        0;
    return count > 0;
  }

  static Future<List<Map<String, dynamic>>> getUnmessagedLeads({
    String? type,
    int limit = 50,
  }) async {
    final db = await DatabaseService.db;
    String where = 'message_sent = 0 OR message_sent IS NULL';
    List<dynamic> args = [];
    if (type != null) {
      where += ' AND type = ?';
      args.add(type);
    }
    return await db.query(
      'leads',
      where: where,
      whereArgs: args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  static Future<void> bulkUpdateMessageStatus({
    required List<int> leadIds,
    required bool sent,
    String? status,
    String? messageType,
  }) async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in leadIds) {
      await db.update(
        'leads',
        {
          'message_sent': sent ? 1 : 0,
          'message_status': status,
          'message_timestamp': now,
          'message_type': messageType,
          if (sent) 'last_contacted': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ✅ Clean SMS sent log older than 24h so numbers can receive SMS next day
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
    if (deleted > 0) debugPrint('🧹 Cleaned $deleted sms_sent_log entries');
  }

  // ✅ Clear all user data on logout — so new user gets fresh DB
  static Future<void> clearAllUserData() async {
    final db = await DatabaseService.db;
    await db.delete('leads');
    await db.delete('auto_sms_logs');
    await db.delete('auto_sms_rules');
    await db.delete('templates');
    await db.delete('blocked_numbers');
    await db.delete('processed_calls');
    await db.delete('scheduled_sms');
    await db.delete('sms_sent_log');
    await db.delete('app_notifications');
    // Re-insert default templates for next user
    await _insertDefaultTemplates(db);
    debugPrint('🧹 All user data cleared on logout');
  }
}
