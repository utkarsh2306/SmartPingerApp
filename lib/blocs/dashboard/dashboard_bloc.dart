import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/core/api_config.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/background_service.dart';
import 'package:message_me/service/notification_service.dart';

// ── Events ────────────────────────────────────────────────────────
abstract class DashboardEvent {}
class DashboardLoadEvent extends DashboardEvent {}
class DashboardRefreshAnalyticsEvent extends DashboardEvent {}
class DashboardToggleAutoTriggerEvent extends DashboardEvent {}
class DashboardTabChangedEvent extends DashboardEvent {
  final int index;
  DashboardTabChangedEvent(this.index);
}

// ── States ────────────────────────────────────────────────────────
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
      status:            status            ?? this.status,
      tabIndex:          tabIndex          ?? this.tabIndex,
      autoTriggerActive: autoTriggerActive ?? this.autoTriggerActive,
      user:              user              ?? this.user,
      subscription:      subscription      ?? this.subscription,
      analytics:         analytics         ?? this.analytics,
      errorMessage:      errorMessage      ?? this.errorMessage,
      requiresLogin:     requiresLogin     ?? this.requiresLogin,
      requiresUpgrade:   requiresUpgrade   ?? this.requiresUpgrade,
    );
  }
}

// ── BLoC ──────────────────────────────────────────────────────────
class DashboardBloc {
  static final DashboardBloc _instance = DashboardBloc._internal();
  factory DashboardBloc() => _instance;
  DashboardBloc._internal();

  final ValueNotifier<DashboardState> state = ValueNotifier(
    const DashboardState());

  bool _dataLoaded = false;

  // ✅ Fixed MethodChannel — uses new package name
  static const _platform = MethodChannel('com.nextracom.smartpinger/settings');

  void add(DashboardEvent event) {
    if (event is DashboardLoadEvent)            _onLoad();
    if (event is DashboardRefreshAnalyticsEvent) _onRefreshAnalytics();
    if (event is DashboardToggleAutoTriggerEvent) _onToggle();
    if (event is DashboardTabChangedEvent)       _onTabChanged(event.index);
  }

  // ── Load ──────────────────────────────────────────────────────
  Future<void> _onLoad() async {
    if (_dataLoaded) {
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

    // ✅ Load user profile FIRST — never blocked by subscription middleware
    await _loadUserProfile(token);

    // ✅ Load subscription separately — handle errors gracefully
    await _loadSubscription(token);

    await _loadAnalytics();
    _refreshAutoTriggerStatus();

    state.value = state.value.copyWith(status: DashboardStatus.loaded);
    _dataLoaded = true;
  }

  // ── Subscription ──────────────────────────────────────────────
  // ✅ Fixed: subscription expiry is shown as info, NOT a blocker
  // Users should see the dashboard even if subscription expired
  // Only show upgrade prompt as a banner — don't lock them out
  Future<void> _loadSubscription(String token) async {
    try {
      final res = await http.get(
        Uri.parse(ApiConfig.mySubscription),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.receiveTimeout);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          final sub = data['data'] as Map<String, dynamic>;
          state.value = state.value.copyWith(subscription: sub);

          // ✅ Only show upgrade dialog if API explicitly says so
          // Don't trigger on 403 — that could be a middleware issue
          if (sub['requires_upgrade'] == true) {
            state.value = state.value.copyWith(requiresUpgrade: true);
          }
        }
      } else if (res.statusCode == 401) {
        // Real auth failure — logout
        state.value = state.value.copyWith(requiresLogin: true);
      } else if (res.statusCode == 403) {
        final data = json.decode(res.body);
        // ✅ Only treat as expired if API sends the exact code
        // NOT just any 403
        if (data['code'] == 'SUBSCRIPTION_EXPIRED') {
          // Show expired banner but DON'T lock dashboard
          // User can still see their data
          state.value = state.value.copyWith(
            subscription: {
              'plan': 'expired',
              'is_active': false,
              'sms_limit': 0,
              'sms_used': 0,
              'sms_remaining': 0,
              'requires_upgrade': true,
            },
          );
          // ✅ Don't set requiresUpgrade: true here — that shows blocking dialog
          // Instead show it as a banner on dashboard
        }
        // Any other 403 — ignore, don't redirect
      }
      // Any other status (500, network error) — ignore, show dashboard anyway
    } catch (_) {
      // Network error loading subscription — don't block dashboard
    }
  }

  // ── User profile ──────────────────────────────────────────────
  Future<void> _loadUserProfile(String token) async {
    try {
      final res = await http.get(
        Uri.parse(ApiConfig.me),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.receiveTimeout);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true) {
          final user = data['data'] as Map<String, dynamic>;
          state.value = state.value.copyWith(user: user);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', user['email'] ?? '');
          await prefs.setString('user_name',  user['full_name'] ?? '');
          await prefs.setString('user_phone', user['phone'] ?? '');
        }
      } else if (res.statusCode == 401) {
        state.value = state.value.copyWith(requiresLogin: true);
      }
    } catch (_) {}
  }

  // ── Analytics ─────────────────────────────────────────────────
  Future<void> _loadAnalytics() async {
    try {
      final db = await DatabaseService.db;
      final totalLeads     = (await db.query('leads')).length;
      final totalSmsSent   = (await db.query('auto_sms_logs')).length;
      final activeRules    = (await db.query('auto_sms_rules', where: 'is_active = 1')).length;
      final totalTemplates = (await db.query('templates')).length;

      state.value = state.value.copyWith(analytics: {
        'totalLeads':    totalLeads,
        'totalSmsSent':  totalSmsSent,
        'activeRules':   activeRules,
        'templates':     totalTemplates,
      });
    } catch (_) {}
  }

  Future<void> _onRefreshAnalytics() async {
    await _loadAnalytics();
  }

  // ── Auto trigger ──────────────────────────────────────────────
  void _refreshAutoTriggerStatus() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ Use pref as source of truth, not just service running state
    // Service may be running but trigger could be disabled by user
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
      try { await _platform.invokeMethod('stopCallDetection'); } catch (_) {}
      try { await _platform.invokeMethod('syncAutoTrigger', {'enabled': false}); } catch (_) {}
    } else {
      await BackgroundServiceManager.start();
      await prefs.setBool('auto_trigger_enabled', true);
      await prefs.setBool('user_disabled_trigger', false);
      await BackgroundServiceManager.syncRulesToNative(enabled: true);
      try { await _platform.invokeMethod('startCallDetection'); } catch (_) {}
      try { await _platform.invokeMethod('syncAutoTrigger', {'enabled': true}); } catch (_) {}
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
        final rules = await db.query('auto_sms_rules',
          where: 'trigger_type = ? AND is_active = 1',
          whereArgs: [callType], limit: 1);
        if (rules.isEmpty) continue;

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
          if (callType == 'missed')    missedMsg    = message;
          if (callType == 'incoming')  incomingMsg  = message;
          if (callType == 'outgoing')  outgoingMsg  = message;
        }
      }

      await _platform.invokeMethod('syncRules', {
        'enabled':  true,
        'missed':   missedMsg,
        'incoming': incomingMsg,
        'outgoing': outgoingMsg,
      });
    } catch (_) {}
  }

  // ── Tab ───────────────────────────────────────────────────────
  void _onTabChanged(int index) {
    state.value = state.value.copyWith(tabIndex: index);
  }

  // ── Public methods ────────────────────────────────────────────
  Future<void> refreshUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) await _loadUserProfile(token);
  }

  void reset() {
    _dataLoaded = false;
    state.value = const DashboardState();
  }
}
