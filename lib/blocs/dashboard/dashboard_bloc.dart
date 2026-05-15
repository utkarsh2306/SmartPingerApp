// lib/blocs/dashboard/dashboard_bloc.dart
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

// ── BLoC (using ValueNotifier for simplicity without bloc package) ─
class DashboardBloc {
  // ✅ Singleton so state persists across tab switches
  static final DashboardBloc _instance = DashboardBloc._internal();
  factory DashboardBloc() => _instance;
  DashboardBloc._internal();

  final ValueNotifier<DashboardState> state = ValueNotifier(
    const DashboardState(),
  );

  bool _dataLoaded = false; // ✅ prevents reload on every visit

  void add(DashboardEvent event) {
    debugPrint('📢 DashboardBloc event received: ${event.runtimeType}');
    if (event is DashboardLoadEvent) _onLoad();
    if (event is DashboardRefreshAnalyticsEvent) _onRefreshAnalytics();
    if (event is DashboardToggleAutoTriggerEvent) _onToggle();
    if (event is DashboardTabChangedEvent) _onTabChanged(event.index);
  }

  // ── Load ──────────────────────────────────────────────────────
  Future<void> _onLoad() async {
    debugPrint('========== DASHBOARD LOAD START ==========');

    // ✅ If already loaded, don't show loading spinner again
    if (_dataLoaded) {
      debugPrint('✅ Data already loaded, skipping full reload');
      debugPrint('🔄 Refreshing auto trigger status only...');
      _refreshAutoTriggerStatus();
      debugPrint('========== DASHBOARD LOAD END (cached) ==========');
      return;
    }

    debugPrint('🔄 First time load, fetching fresh data...');
    state.value = state.value.copyWith(status: DashboardStatus.loading);
    debugPrint('📊 Dashboard status set to: loading');

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final isGuest = prefs.getBool('is_guest') ?? false;

    debugPrint('🔑 Token present: ${token != null}');
    debugPrint('👤 Is guest mode: $isGuest');

    if (isGuest) {
      debugPrint('🎭 Loading guest dashboard...');
      state.value = state.value.copyWith(
        status: DashboardStatus.loaded,
        user: {
          'full_name': 'Guest User',
          'email': 'guest@example.com',
          'phone': '',
        },
        subscription: {
          'plan': 'Guest',
          'is_active': true,
          'sms_limit': 50,
          'sms_used': 0,
          'sms_remaining': 50,
        },
      );
      debugPrint('✅ Guest dashboard loaded');
      await _loadAnalytics();
      _refreshAutoTriggerStatus();
      _dataLoaded = true;
      debugPrint('========== DASHBOARD LOAD END (guest) ==========');
      return;
    }

    if (token == null) {
      debugPrint('❌ No token found, requires login');
      state.value = state.value.copyWith(requiresLogin: true);
      debugPrint('========== DASHBOARD LOAD END (no token) ==========');
      return;
    }

    debugPrint('🔐 Loading subscription for authenticated user...');
    // Load subscription
    try {
      final url = Uri.parse(ApiConfig.mySubscription);
      debugPrint('🌐 Subscription URL: $url');

      final res = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(ApiConfig.receiveTimeout);

      debugPrint('📥 Subscription response status: ${res.statusCode}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        debugPrint('📦 Subscription data: $data');

        if (data['success'] == true) {
          final sub = data['data'] as Map<String, dynamic>;
          debugPrint('✅ Subscription loaded: ${sub['plan']} plan');
          debugPrint(
            '📊 SMS limit: ${sub['sms_limit']}, Used: ${sub['sms_used']}',
          );

          state.value = state.value.copyWith(subscription: sub);
          if (sub['requires_upgrade'] == true) {
            debugPrint('⚠️ Subscription requires upgrade');
            state.value = state.value.copyWith(
              status: DashboardStatus.loaded,
              requiresUpgrade: true,
            );
            _dataLoaded = true;
            debugPrint(
              '========== DASHBOARD LOAD END (requires upgrade) ==========',
            );
            return;
          }
        } else {
          debugPrint('⚠️ Subscription API returned success=false');
        }
      } else if (res.statusCode == 401) {
        debugPrint('❌ Subscription API returned 401 - Unauthorized');
        state.value = state.value.copyWith(requiresLogin: true);
        debugPrint('========== DASHBOARD LOAD END (unauthorized) ==========');
        return;
      } else if (res.statusCode == 403) {
        final data = json.decode(res.body);
        debugPrint('⚠️ Subscription API returned 403 - Forbidden');
        debugPrint('📦 Response data: $data');

        if (data['code'] == 'SUBSCRIPTION_EXPIRED') {
          debugPrint('⚠️ Subscription expired, requires upgrade');
          state.value = state.value.copyWith(
            status: DashboardStatus.loaded,
            requiresUpgrade: true,
          );
          _dataLoaded = true;
          debugPrint('========== DASHBOARD LOAD END (expired) ==========');
          return;
        }
        state.value = state.value.copyWith(requiresLogin: true);
        debugPrint('========== DASHBOARD LOAD END (forbidden) ==========');
        return;
      } else {
        debugPrint(
          '⚠️ Unexpected subscription response status: ${res.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('💥 Subscription loading error: $e');
      debugPrint('📚 Stack trace: $stackTrace');
    }

    // Load user profile
    debugPrint('👤 Loading user profile...');
    await _loadUserProfile(token);

    debugPrint('📊 Loading analytics...');
    await _loadAnalytics();

    debugPrint('🔄 Refreshing auto trigger status...');
    _refreshAutoTriggerStatus();

    state.value = state.value.copyWith(status: DashboardStatus.loaded);
    _dataLoaded = true;
    debugPrint('✅ Dashboard fully loaded');
    debugPrint('========== DASHBOARD LOAD END (success) ==========');
  }

  // ── User profile ──────────────────────────────────────────────
  Future<void> _loadUserProfile(String token) async {
    debugPrint('🔍 Fetching user profile...');
    try {
      final url = Uri.parse(ApiConfig.me);
      debugPrint('🌐 Profile URL: $url');

      final res = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(ApiConfig.receiveTimeout);

      debugPrint('📥 Profile response status: ${res.statusCode}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        debugPrint('📦 Profile data: ${data['data']}');

        if (data['success'] == true) {
          final user = data['data'] as Map<String, dynamic>;
          debugPrint(
            '✅ User profile loaded: ${user['full_name']} (${user['email']})',
          );

          state.value = state.value.copyWith(user: user);
          final prefs = await SharedPreferences.getInstance();

          await prefs.setString('user_email', user['email'] ?? '');
          await prefs.setString('user_name', user['full_name'] ?? '');
          await prefs.setString('user_phone', user['phone'] ?? '');
          debugPrint('💾 User data saved to SharedPreferences');
        } else {
          debugPrint('⚠️ Profile API returned success=false');
        }
      } else if (res.statusCode == 401) {
        debugPrint('❌ Profile API returned 401 - Unauthorized');
        state.value = state.value.copyWith(requiresLogin: true);
      } else {
        debugPrint('⚠️ Unexpected profile response status: ${res.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('💥 Profile loading error: $e');
      debugPrint('📚 Stack trace: $stackTrace');
    }
  }

  // ── Analytics ─────────────────────────────────────────────────
  Future<void> _loadAnalytics() async {
    debugPrint('📈 Loading analytics from local database...');
    try {
      final db = await DatabaseService.db;

      final totalLeads = (await db.query('leads')).length;
      debugPrint('📊 Total leads: $totalLeads');

      final totalSmsSent = (await db.query('auto_sms_logs')).length;
      debugPrint('📊 Total SMS sent: $totalSmsSent');

      final activeRules = (await db.query(
        'auto_sms_rules',
        where: 'is_active = 1',
      )).length;
      debugPrint('📊 Active rules: $activeRules');

      final totalTemplates = (await db.query('templates')).length;
      debugPrint('📊 Total templates: $totalTemplates');

      state.value = state.value.copyWith(
        analytics: {
          'totalLeads': totalLeads,
          'totalSmsSent': totalSmsSent,
          'activeRules': activeRules,
          'templates': totalTemplates,
        },
      );
      debugPrint('✅ Analytics loaded successfully');
    } catch (e, stackTrace) {
      debugPrint('💥 Analytics loading error: $e');
      debugPrint('📚 Stack trace: $stackTrace');
    }
  }

  Future<void> _onRefreshAnalytics() async {
    debugPrint('🔄 Manual analytics refresh requested');
    await _loadAnalytics();
    debugPrint('✅ Analytics refresh complete');
  }

  // ── Auto trigger ──────────────────────────────────────────────
  void _refreshAutoTriggerStatus() async {
    debugPrint('🔄 Refreshing auto trigger status...');
    final isRunning = await BackgroundServiceManager.isRunning();
    debugPrint('🎯 Background service running: $isRunning');
    state.value = state.value.copyWith(autoTriggerActive: isRunning);
    NotificationService().showPersistentAutoTriggerNotification(isRunning);
    debugPrint('✅ Auto trigger status updated: $isRunning');
  }

  Future<void> _onToggle() async {
    debugPrint('========== AUTO TRIGGER TOGGLE ==========');
    final isRunning = state.value.autoTriggerActive;
    debugPrint('Current state: ${isRunning ? "RUNNING" : "STOPPED"}');
    debugPrint('Action: ${isRunning ? "STOPPING" : "STARTING"}');

    final prefs = await SharedPreferences.getInstance();
    const platform = MethodChannel('com.example.message_me/settings');

    if (isRunning) {
      debugPrint('🛑 Stopping background service...');
      await BackgroundServiceManager.stop();
      await prefs.setBool('auto_trigger_enabled', false);
      await prefs.setBool('user_disabled_trigger', true);
      debugPrint('✅ auto_trigger_enabled set to false');
      debugPrint('✅ user_disabled_trigger set to true');

      debugPrint('📡 Syncing rules to native (enabled: false)...');
      await BackgroundServiceManager.syncRulesToNative(enabled: false);

      debugPrint('📞 Invoking stopCallDetection method channel...');
      try {
        await platform.invokeMethod('stopCallDetection');
        debugPrint('✅ stopCallDetection invoked successfully');
      } catch (e) {
        debugPrint('⚠️ stopCallDetection failed: $e');
      }
    } else {
      debugPrint('▶️ Starting background service...');
      await BackgroundServiceManager.start();
      await prefs.setBool('auto_trigger_enabled', true);
      await prefs.setBool('user_disabled_trigger', false);
      debugPrint('✅ auto_trigger_enabled set to true');
      debugPrint('✅ user_disabled_trigger set to false');

      debugPrint('📡 Syncing rules to native (enabled: true)...');
      await BackgroundServiceManager.syncRulesToNative(enabled: true);

      debugPrint('📞 Invoking startCallDetection method channel...');
      try {
        await platform.invokeMethod('startCallDetection');
        debugPrint('✅ startCallDetection invoked successfully');
      } catch (e) {
        debugPrint('⚠️ startCallDetection failed: $e');
      }

      debugPrint('🔄 Syncing rules...');
      await _syncRules(platform);
    }

    debugPrint('⏳ Waiting 500ms before refreshing status...');
    await Future.delayed(const Duration(milliseconds: 500));
    _refreshAutoTriggerStatus();
    debugPrint('========== AUTO TRIGGER TOGGLE COMPLETE ==========');
  }

  Future<void> _syncRules(MethodChannel platform) async {
    debugPrint('🔄 Syncing SMS rules to native platform...');
    try {
      final db = await DatabaseService.db;
      String? missedMsg, incomingMsg, outgoingMsg;

      for (final callType in ['missed', 'incoming', 'outgoing']) {
        debugPrint('📝 Processing rules for call type: $callType');
        final rules = await db.query(
          'auto_sms_rules',
          where: 'trigger_type = ? AND is_active = 1',
          whereArgs: [callType],
          limit: 1,
        );

        if (rules.isEmpty) {
          debugPrint('⚠️ No active rule found for $callType');
          continue;
        }

        final rule = rules.first;
        String message = '';
        final customMsg = rule['custom_message'] as String?;

        if (customMsg != null && customMsg.isNotEmpty) {
          message = customMsg;
          debugPrint(
            '📝 Using custom message for $callType: "${message.substring(0, message.length > 50 ? 50 : message.length)}..."',
          );
        } else {
          final templateId = rule['template_id'] as int?;
          debugPrint('📝 Looking for template ID: $templateId');

          if (templateId != null) {
            final templates = await db.query(
              'templates',
              where: 'id = ?',
              whereArgs: [templateId],
            );
            if (templates.isNotEmpty) {
              message = templates.first['message'] as String? ?? '';
              debugPrint(
                '📝 Using template message for $callType: "${message.substring(0, message.length > 50 ? 50 : message.length)}..."',
              );
            } else {
              debugPrint('⚠️ Template ID $templateId not found');
            }
          }
        }

        if (message.isNotEmpty) {
          if (callType == 'missed') missedMsg = message;
          if (callType == 'incoming') incomingMsg = message;
          if (callType == 'outgoing') outgoingMsg = message;
          debugPrint('✅ Rule synced for $callType');
        } else {
          debugPrint('⚠️ No message content for $callType');
        }
      }

      final syncData = {
        'enabled': true,
        'missed': missedMsg,
        'incoming': incomingMsg,
        'outgoing': outgoingMsg,
      };
      debugPrint('📤 Syncing to native: $syncData');

      await platform.invokeMethod('syncRules', syncData);
      debugPrint('✅ Rules synced successfully to native platform');
    } catch (e, stackTrace) {
      debugPrint('❌ syncRules error: $e');
      debugPrint('📚 Stack trace: $stackTrace');
    }
  }

  // ── Tab ───────────────────────────────────────────────────────
  void _onTabChanged(int index) {
    debugPrint(
      '🔄 Tab changed to index: $index (${index == 0
          ? "Dashboard"
          : index == 1
          ? "Leads"
          : "Auto SMS"})',
    );
    state.value = state.value.copyWith(tabIndex: index);
  }

  // ── Public refresh user ───────────────────────────────────────
  Future<void> refreshUserProfile() async {
    debugPrint('🔄 Public refresh user profile called');
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      debugPrint('🔑 Token found, refreshing profile...');
      await _loadUserProfile(token);
      debugPrint('✅ Profile refresh complete');
    } else {
      debugPrint('⚠️ No token found, cannot refresh profile');
    }
  }

  // ── Reset on logout ───────────────────────────────────────────
  void reset() {
    debugPrint('🔄 Resetting DashboardBloc state');
    _dataLoaded = false;
    state.value = const DashboardState();
    debugPrint('✅ DashboardBloc reset complete');
  }
}
