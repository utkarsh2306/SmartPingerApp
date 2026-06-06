import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/core/api_config.dart';
import 'package:message_me/service/admin_notification_service.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/background_service.dart';
import 'package:message_me/service/notification_service.dart';

abstract class DashboardEvent {}

class DashboardLoadEvent extends DashboardEvent {}

class DashboardRefreshAnalyticsEvent extends DashboardEvent {}

class DashboardToggleAutoTriggerEvent extends DashboardEvent {}

class DashboardTabChangedEvent extends DashboardEvent {
  final int index;
  DashboardTabChangedEvent(this.index);
}

enum DashboardStatus { initial, loading, loaded, error }

class DashboardState {
  final DashboardStatus status;
  final int tabIndex;
  final bool autoTriggerActive;
  final Map<String, dynamic> user;
  final Map<String, dynamic> subscription;
  final Map<String, dynamic> analytics;
  final String? errorMessage;
  final bool requiresLogin;
  final bool requiresUpgrade;

  const DashboardState({
    this.status = DashboardStatus.initial,
    this.tabIndex = 0,
    this.autoTriggerActive = false,
    this.user = const {},
    this.subscription = const {},
    this.analytics = const {
      'totalLeads': 0,
      'totalSmsSent': 0,
      'activeRules': 0,
      'templates': 0,
    },
    this.errorMessage,
    this.requiresLogin = false,
    this.requiresUpgrade = false,
  });

  DashboardState copyWith({
    DashboardStatus? status,
    int? tabIndex,
    bool? autoTriggerActive,
    Map<String, dynamic>? user,
    Map<String, dynamic>? subscription,
    Map<String, dynamic>? analytics,
    String? errorMessage,
    bool? requiresLogin,
    bool? requiresUpgrade,
  }) {
    return DashboardState(
      status: status ?? this.status,
      tabIndex: tabIndex ?? this.tabIndex,
      autoTriggerActive: autoTriggerActive ?? this.autoTriggerActive,
      user: user ?? this.user,
      subscription: subscription ?? this.subscription,
      analytics: analytics ?? this.analytics,
      errorMessage: errorMessage ?? this.errorMessage,
      requiresLogin: requiresLogin ?? this.requiresLogin,
      requiresUpgrade: requiresUpgrade ?? this.requiresUpgrade,
    );
  }
}

class DashboardBloc {
  static final DashboardBloc _instance = DashboardBloc._internal();
  factory DashboardBloc() => _instance;
  DashboardBloc._internal();

  final ValueNotifier<DashboardState> state = ValueNotifier(
    const DashboardState(),
  );
  bool _dataLoaded = false;
  static const _platform = MethodChannel('com.nextracom.smartpinger/settings');

  void add(DashboardEvent event) {
    if (event is DashboardLoadEvent) _onLoad();
    if (event is DashboardRefreshAnalyticsEvent) _onRefreshAnalytics();
    if (event is DashboardToggleAutoTriggerEvent) _onToggle();
    if (event is DashboardTabChangedEvent) _onTabChanged(event.index);
  }

  Future<void> _onLoad() async {
    if (_dataLoaded) {
      if (state.value.requiresLogin) {
        state.value = state.value.copyWith(requiresLogin: false);
      }
      _refreshAutoTriggerStatus();
      return;
    }

    state.value = state.value.copyWith(status: DashboardStatus.loading);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null || token.isEmpty) {
      state.value = state.value.copyWith(requiresLogin: true);
      return;
    }

    await _loadUserProfile(token);
    await _loadSubscription(token);
    await _loadAnalytics();
    _refreshAutoTriggerStatus();

    // Fetch admin notifications in background
    AdminNotificationService().fetchAndStore();

    state.value = state.value.copyWith(status: DashboardStatus.loaded);
    _dataLoaded = true;
  }

  Future<void> _loadSubscription(String token) async {
    try {
      final res = await http
          .get(
            Uri.parse(ApiConfig.mySubscription),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(ApiConfig.receiveTimeout);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          final sub = data['data'] as Map<String, dynamic>;
          state.value = state.value.copyWith(subscription: sub);

          final prefs = await SharedPreferences.getInstance();
          final expiry = sub['expiry_date'] ?? sub['subscription_expiry'];
          if (expiry != null) {
            await prefs.setString('subscription_expiry', expiry.toString());
          }

          // ✅ Save active status so Kotlin can check in background
          final isActive = sub['is_active'];
          final isInactive = isActive == false || isActive == 0;
          await prefs.setBool('user_is_active', !isInactive);

          // ✅ Check expiry locally
          bool isExpired = false;
          if (expiry != null) {
            try {
              final expiryDate = DateTime.parse(expiry.toString());
              isExpired = expiryDate.isBefore(DateTime.now());
            } catch (_) {}
          }

          // ✅ Block SMS and show dialog for expired or inactive
          if (sub['requires_upgrade'] == true || isExpired || isInactive) {
            await prefs.setBool('auto_trigger_enabled', false);
            state.value = state.value.copyWith(requiresUpgrade: true);
          }
        }
      } else if (res.statusCode == 403) {
        final data = json.decode(res.body);
        if (data['code'] == 'SUBSCRIPTION_EXPIRED') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auto_trigger_enabled', false);
          await prefs.setBool(
            'user_is_active',
            false,
          ); // ✅ Tell Kotlin user is inactive
          state.value = state.value.copyWith(
            subscription: {
              'plan': 'expired',
              'is_active': false,
              'sms_limit': 0,
              'sms_used': 0,
              'sms_remaining': 0,
            },
            requiresUpgrade: true,
          );
        }
      }
      // 401, 500, network errors — ignore, show dashboard anyway
    } catch (_) {}
  }

  // In dashboard_bloc.dart - Update _loadUserProfile method

  Future<void> _loadUserProfile(String token) async {
    try {
      final res = await http
          .get(
            Uri.parse(ApiConfig.me),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(ApiConfig.receiveTimeout);
      print("user response code ${res.statusCode}");
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          final user = data['data'] as Map<String, dynamic>;
          print("user data ${data}");
          state.value = state.value.copyWith(user: user);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', user['email'] ?? '');
          await prefs.setString('user_name', user['full_name'] ?? '');
          await prefs.setString('user_phone', user['phone'] ?? '');
        }
      } else {
        final data = json.decode(res.body);
        final error = data['error'];
        // ✅ Changed: User not found should trigger requiresUpgrade, not requiresLogin
        if (error.toString().contains("User not found")) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auto_trigger_enabled', false);
          await prefs.setBool('user_is_active', false);
          state.value = state.value.copyWith(
            requiresUpgrade: true,
            user: {}, // Clear user data
          );
        }
      }
    } catch (e) {
      print("user data error ${e}");
      // ✅ Changed: User not found in exception should also trigger requiresUpgrade
      if (e.toString().contains("User not found")) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_trigger_enabled', false);
        await prefs.setBool('user_is_active', false);
        state.value = state.value.copyWith(requiresUpgrade: true, user: {});
      }
    }
  }

  Future<void> _loadAnalytics() async {
    try {
      final db = await DatabaseService.db;
      final totalLeads = (await db.query('leads')).length;
      final totalSmsSent = (await db.query('auto_sms_logs')).length;
      final activeRules = (await db.query(
        'auto_sms_rules',
        where: 'is_active = 1',
      )).length;
      final totalTemplates = (await db.query('templates')).length;
      state.value = state.value.copyWith(
        analytics: {
          'totalLeads': totalLeads,
          'totalSmsSent': totalSmsSent,
          'activeRules': activeRules,
          'templates': totalTemplates,
        },
      );
    } catch (_) {}
  }

  Future<void> _onRefreshAnalytics() async => await _loadAnalytics();

  void _refreshAutoTriggerStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final enabledInPrefs = prefs.getBool('auto_trigger_enabled') ?? false;
    final serviceRunning = await BackgroundServiceManager.isRunning();
    final isActive = enabledInPrefs && serviceRunning;
    state.value = state.value.copyWith(autoTriggerActive: isActive);
    NotificationService().showPersistentAutoTriggerNotification(isActive);
  }

  Future<void> _onToggle() async {
    final isRunning = state.value.autoTriggerActive;
    final prefs = await SharedPreferences.getInstance();

    if (isRunning) {
      await BackgroundServiceManager.stop();
      await prefs.setBool('auto_trigger_enabled', false);
      await prefs.setBool('user_disabled_trigger', true);
      await BackgroundServiceManager.syncRulesToNative(enabled: false);
      try {
        await _platform.invokeMethod('stopCallDetection');
      } catch (_) {}
      try {
        await _platform.invokeMethod('syncAutoTrigger', {'enabled': false});
      } catch (_) {}
    } else {
      await BackgroundServiceManager.start();
      await prefs.setBool('auto_trigger_enabled', true);
      await prefs.setBool('user_disabled_trigger', false);
      await BackgroundServiceManager.syncRulesToNative(enabled: true);
      try {
        await _platform.invokeMethod('startCallDetection');
      } catch (_) {}
      try {
        await _platform.invokeMethod('syncAutoTrigger', {'enabled': true});
      } catch (_) {}
      await _syncRules();
    }

    await Future.delayed(const Duration(milliseconds: 500));
    _refreshAutoTriggerStatus();
  }

  Future<void> _syncRules() async {
    try {
      final db = await DatabaseService.db;
      String? missedMsg, incomingMsg, outgoingMsg;

      for (final callType in ['missed', 'incoming', 'outgoing']) {
        final rules = await db.query(
          'auto_sms_rules',
          where: 'trigger_type = ? AND is_active = 1',
          whereArgs: [callType],
          limit: 1,
        );
        if (rules.isEmpty) continue;

        final rule = rules.first;
        String message = '';
        final customMsg = rule['custom_message'] as String?;

        if (customMsg != null && customMsg.isNotEmpty) {
          message = customMsg;
        } else {
          final tid = rule['template_id'] as int?;
          if (tid != null) {
            final t = await db.query(
              'templates',
              where: 'id = ?',
              whereArgs: [tid],
            );
            if (t.isNotEmpty) message = t.first['message'] as String? ?? '';
          }
        }

        if (message.isNotEmpty) {
          if (callType == 'missed') missedMsg = message;
          if (callType == 'incoming') incomingMsg = message;
          if (callType == 'outgoing') outgoingMsg = message;
        }
      }

      await _platform.invokeMethod('syncRules', {
        'enabled': true,
        'missed': missedMsg,
        'incoming': incomingMsg,
        'outgoing': outgoingMsg,
      });
    } catch (_) {}
  }

  void _onTabChanged(int index) =>
      state.value = state.value.copyWith(tabIndex: index);

  Future<void> refreshUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) await _loadUserProfile(token);
  }

  void reset() {
    _dataLoaded = false;
    state.value = const DashboardState(
      requiresLogin: false,
      requiresUpgrade: false,
    );
  }
}
