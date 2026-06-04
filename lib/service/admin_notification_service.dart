// lib/service/admin_notification_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/core/api_config.dart';
import 'package:message_me/service/notification_service.dart';

/// Fetches admin-sent notifications from the server and
/// stores them locally so they appear in the notification screen.
class AdminNotificationService {
  static final AdminNotificationService _instance =
      AdminNotificationService._internal();
  factory AdminNotificationService() => _instance;
  AdminNotificationService._internal();

  static const String _lastFetchKey = 'admin_notif_last_fetch';
  static const String _seenIdsKey   = 'admin_notif_seen_ids';

  /// Call this on app start and periodically (every 30 min is fine)
  Future<void> fetchAndStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null || token.isEmpty) return;

      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final data = json.decode(res.body);
      if (data['success'] != true) return;

      final notifications = data['data'] as List<dynamic>;
      if (notifications.isEmpty) return;

      // Get already-seen notification IDs
      final seenIds = (prefs.getStringList(_seenIdsKey) ?? []).toSet();
      final newNotifications = <Map<String, dynamic>>[];

      for (final n in notifications) {
        final id = n['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          newNotifications.add(n as Map<String, dynamic>);
          seenIds.add(id);
        }
      }

      if (newNotifications.isEmpty) return;

      // Store new notifications locally
      final notifService = NotificationService();
      for (final n in newNotifications) {
        await notifService.addNotification(
          title:   n['title'] as String? ?? 'Smart Pinger',
          message: n['message'] as String? ?? '',
          type:    'admin',
          relatedId: n['id']?.toString(),
        );
      }

      // Save seen IDs so we don't show duplicates
      await prefs.setStringList(_seenIdsKey, seenIds.toList());
      await prefs.setInt(_lastFetchKey, DateTime.now().millisecondsSinceEpoch);

      debugPrint('✅ Fetched ${newNotifications.length} new admin notifications');
    } catch (e) {
      debugPrint('AdminNotificationService error: $e');
    }
  }
}
