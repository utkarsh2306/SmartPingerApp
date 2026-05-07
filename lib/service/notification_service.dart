import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:message_me/service/database_service.dart';

class NotificationModel {
  final int? id;
  final String title;
  final String message;
  final String type; // 'sms_sent', 'call_detected', 'rule_triggered', 'system'
  final String? relatedId;
  final DateTime timestamp;
  bool isRead;

  NotificationModel({
    this.id,
    required this.title,
    required this.message,
    required this.type,
    this.relatedId,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type,
      'related_id': relatedId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'is_read': isRead ? 1 : 0,
    };
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      message: map['message'] as String,
      type: map['type'] as String,
      relatedId: map['related_id'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isRead: (map['is_read'] as int) == 1,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // ValueNotifier for real-time updates
  final ValueNotifier<List<NotificationModel>> notificationsNotifier =
      ValueNotifier([]);
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier(0);

  Future<Database> get _db async => await DatabaseService.db;

  // Initialize notifications table
  Future<void> initTable() async {
    final db = await _db;
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
    await loadNotifications();
  }

  // Load all notifications
  Future<void> loadNotifications() async {
    final db = await _db;
    final results = await db.query(
      'app_notifications',
      orderBy: 'timestamp DESC',
    );

    final notifications = results
        .map((r) => NotificationModel.fromMap(r))
        .toList();
    notificationsNotifier.value = notifications;
    _updateUnreadCount();
  }

  // Add new notification
  Future<void> addNotification({
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final notification = NotificationModel(
      title: title,
      message: message,
      type: type,
      relatedId: relatedId,
      timestamp: DateTime.now(),
      isRead: false,
    );

    final db = await _db;
    await db.insert('app_notifications', notification.toMap());
    await loadNotifications();
  }

  // Mark as read
  Future<void> markAsRead(int id) async {
    final db = await _db;
    await db.update(
      'app_notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadNotifications();
  }

  // Mark all as read
  Future<void> markAllAsRead() async {
    final db = await _db;
    await db.update('app_notifications', {'is_read': 1}, where: 'is_read = 0');
    await loadNotifications();
  }

  // Delete notification
  Future<void> deleteNotification(int id) async {
    final db = await _db;
    await db.delete('app_notifications', where: 'id = ?', whereArgs: [id]);
    await loadNotifications();
  }

  // Clear all notifications
  Future<void> clearAll() async {
    final db = await _db;
    await db.delete('app_notifications');
    await loadNotifications();
  }

  // Delete by type
  Future<void> deleteByType(String type) async {
    final db = await _db;
    await db.delete('app_notifications', where: 'type = ?', whereArgs: [type]);
    await loadNotifications();
  }

  // Get unread count
  void _updateUnreadCount() {
    final unreadCount = notificationsNotifier.value
        .where((n) => !n.isRead)
        .length;
    unreadCountNotifier.value = unreadCount;
  }

  // Auto-add notifications for app events
  Future<void> notifySmsSent(String phone, String templateName) async {
    await addNotification(
      title: 'SMS Sent Successfully',
      message: 'Message sent to $phone using template: $templateName',
      type: 'sms_sent',
      relatedId: phone,
    );
  }

  Future<void> notifyBulkSmsCompleted(
    int count,
    int success,
    int failed,
  ) async {
    await addNotification(
      title: 'Bulk SMS Completed',
      message: 'Sent $success out of $count messages. Failed: $failed',
      type: 'bulk_sms',
    );
  }

  Future<void> notifyCallDetected(String phone, String callType) async {
    await addNotification(
      title: 'Call Detected',
      message: '$callType call from $phone',
      type: 'call_detected',
      relatedId: phone,
    );
  }

  Future<void> notifyRuleTriggered(String ruleName, String phone) async {
    await addNotification(
      title: 'Auto Rule Triggered',
      message: 'Rule "$ruleName" triggered for $phone',
      type: 'rule_triggered',
      relatedId: phone,
    );
  }

  Future<void> notifyTemplateCreated(String templateName) async {
    await addNotification(
      title: 'Template Created',
      message: 'New template "$templateName" added to library',
      type: 'system',
    );
  }

  Future<void> notifyLeadImported(int count) async {
    await addNotification(
      title: 'Leads Imported',
      message: 'Successfully imported $count new leads',
      type: 'system',
    );
  }

  Future<void> notifyAutoTriggerStatus(bool isActive) async {
    await addNotification(
      title: isActive ? 'Auto-Trigger Enabled' : 'Auto-Trigger Disabled',
      message: isActive
          ? 'Automatic SMS sending is now active'
          : 'Automatic SMS sending has been turned off',
      type: 'system',
    );
  }

  Future<void> showPersistentAutoTriggerNotification(bool isRunning) async {}
}
