import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:message_me/core/api_config.dart';
import 'package:message_me/service/background_service.dart';
import 'package:message_me/service/notification_service.dart';

// ── Local notifications setup ─────────────────────────────────────
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'admin_push_channel',
  'Admin Notifications',
  description: 'Notifications from Smart Pinger admin',
  importance: Importance.high,
  showBadge: true,
);

// ✅ Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await _handleFcmMessage(message);
}

Future<void> _handleFcmMessage(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'];
  final prefs = await SharedPreferences.getInstance();

  switch (type) {
    case 'account_deactivated':
      await prefs.setBool('user_is_active', false);
      await prefs.setBool('auto_trigger_enabled', false);
      await BackgroundServiceManager.stop();
      await BackgroundServiceManager.syncRulesToNative(enabled: false);
      await _showLocalNotification(
        'Account Deactivated',
        'Your account has been deactivated. Auto SMS has been stopped. Contact 9536235656 to reactivate.',
      );
      break;

    case 'account_activated':
      await prefs.setBool('user_is_active', true);
      await _showLocalNotification(
        'Account Activated',
        'Your account has been reactivated. Smart Pinger is active again!',
      );
      break;

    case 'subscription_expired':
      await prefs.setBool('auto_trigger_enabled', false);
      final expiry = data['expiry_date'];
      if (expiry != null) await prefs.setString('subscription_expiry', expiry);
      await BackgroundServiceManager.stop();
      await BackgroundServiceManager.syncRulesToNative(enabled: false);
      await _showLocalNotification(
        'Subscription Expired',
        'Your subscription has expired. Auto SMS has been stopped. Contact 9536235656 to renew.',
      );
      break;

    case 'subscription_renewed':
      final expiry = data['expiry_date'];
      if (expiry != null) await prefs.setString('subscription_expiry', expiry);
      await prefs.setBool('user_is_active', true);
      await _showLocalNotification(
        'Subscription Renewed ✅',
        'Your subscription has been renewed. Smart Pinger is active!',
      );
      break;

    case 'admin_notification':
      final title = data['title'] ?? 'Smart Pinger';
      final msg = data['message'] ?? '';
      await NotificationService().addNotification(
        title: title,
        message: msg,
        type: 'admin',
      );
      await _showLocalNotification(title, msg);
      break;
  }
}

Future<void> _showLocalNotification(String title, String body) async {
  try {
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          playSound: true,
        ),
      ),
    );
  } catch (e) {
    debugPrint('FCM notification error: $e');
  }
}

class FcmService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;

  static Future<void> initialize() async {
    try {
      // ✅ Initialize local notifications
      await flutterLocalNotificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse:
            (NotificationResponse details) async {},
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      // ✅ Request permission
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized)
        return;

      // ✅ Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // ✅ Handle foreground messages
      FirebaseMessaging.onMessage.listen((message) async {
        await _handleFcmMessage(message);
        final type = message.data['type'];
        if (type == 'account_deactivated' ||
            type == 'account_activated' ||
            type == 'subscription_expired' ||
            type == 'subscription_renewed') {
          _reloadDashboard();
          // ✅ For activation/renewal — also signal dialog dismiss
          if (type == 'account_activated' || type == 'subscription_renewed') {
            dismissTrigger.value++;
          }
        }
      });

      // ✅ Handle app opened from terminated state
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        await _handleFcmMessage(initialMessage);
        _reloadDashboard();
      }

      // ✅ Handle app opened from background via notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((message) async {
        await _handleFcmMessage(message);
        _reloadDashboard();
      });

      // ✅ Save token to backend
      await _saveTokenToServer();

      // ✅ Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        await _saveTokenToServer(newToken);
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }

  static Future<void> _saveTokenToServer([String? token]) async {
    try {
      final fcmToken = token ?? await _firebaseMessaging.getToken();
      if (fcmToken == null) return;

      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('token');
      if (authToken == null) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/user/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': fcmToken}),
      );
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  static Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
    } catch (_) {}
  }

  // ✅ Notifier that dashboard listens to for reload triggers
  static final ValueNotifier<int> reloadTrigger = ValueNotifier(0);

  // ✅ Notifier to dismiss expired dialog when account is reactivated
  static final ValueNotifier<int> dismissTrigger = ValueNotifier(0);

  static void _reloadDashboard() {
    reloadTrigger.value++;
  }
}
