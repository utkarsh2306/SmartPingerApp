import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import '../models/lead.dart';
import 'database_service.dart';

class CallLogService {
  static Future<void> syncLogs(String type) async {
    // Get all logs first (unavoidable with this package)
    final allLogs = await CallLog.get();

    // Filter manually by date (last 10 days)
    final tenDaysAgo = DateTime.now()
        .subtract(const Duration(days: 10))
        .millisecondsSinceEpoch;

    final logs = allLogs.where((log) {
      return log.timestamp != null && log.timestamp! >= tenDaysAgo;
    }).toList();

    // Limit to last 500 calls (most recent first)
    logs.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
    final limitedLogs = logs.length > 500 ? logs.sublist(0, 500) : logs;

    final db = await DatabaseService.db;

    for (var log in limitedLogs) {
      if (log.number == null) continue;

      // Determine call type
      bool isMatch = false;
      if (type == 'incoming' && log.callType == CallType.incoming) {
        isMatch = true;
      } else if (type == 'outgoing' && log.callType == CallType.outgoing) {
        isMatch = true;
      } else if (type == 'missed' && log.callType == CallType.missed) {
        isMatch = true;
      }

      if (isMatch) {
        // CHECK IF CALL ALREADY EXISTS BEFORE INSERTING
        final existingCall = await db.query(
          'leads',
          where: 'phone = ? AND type = ? AND timestamp = ?',
          whereArgs: [log.number!, type, log.timestamp ?? 0],
        );

        // Only insert if not already exists
        if (existingCall.isEmpty) {
          await db.insert(
            'leads',
            Lead(
              phone: log.number!,
              type: type,
              timestamp: log.timestamp ?? 0,
            ).toMap(),
          );
          debugPrint('✅ Inserted new lead: ${log.number}');
        } else {
          debugPrint('⏭️ Skipping duplicate: ${log.number}');
        }
      }
    }
  }
}
