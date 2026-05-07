import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:message_me/service/background_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/screens/auto_sms_screen.dart';
import 'package:message_me/screens/block_list_screen.dart';
import 'package:message_me/screens/bulk_sms_screen.dart';
import 'package:message_me/screens/login_screen.dart';
import 'package:message_me/screens/message_library_screen.dart';
import 'package:message_me/screens/notification_screen.dart';
import 'package:message_me/screens/settings_screen.dart';
import 'package:message_me/screens/sms_anyone_screen.dart';
import 'package:message_me/screens/status_screen.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/notification_service.dart';

const String baseUrl =
    'http://ec2-65-2-170-60.ap-south-1.compute.amazonaws.com:8080';

class DashboardStateNotifier {
  static final dashboardNotifier = ValueNotifier<int>(0);
  static final autoTriggerNotifier = ValueNotifier<bool>(false);
  static final analyticsNotifier = ValueNotifier<Map<String, dynamic>>({
    'totalLeads': 0,
    'totalSmsSent': 0,
    'activeRules': 0,
    'templates': 0,
  });
  static final userNotifier = ValueNotifier<Map<String, dynamic>>({});
  static final subscriptionNotifier = ValueNotifier<Map<String, dynamic>>({});

  static void updateIndex(int i) => dashboardNotifier.value = i;
  static void updateAutoTriggerStatus(bool s) => autoTriggerNotifier.value = s;
  static void updateAnalytics(Map<String, dynamic> a) =>
      analyticsNotifier.value = a;
  static void updateUser(Map<String, dynamic> u) => userNotifier.value = u;
  static void updateSubscription(Map<String, dynamic> s) =>
      subscriptionNotifier.value = s;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  static const _primary = Color(0xFF5B67F1);

  @override
  void initState() {
    super.initState();
    _checkSubscriptionAndLoadData();
  }

  // ── Data loading (unchanged logic) ──────────────────────────────

  Future<void> _checkSubscriptionAndLoadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final isGuest = prefs.getBool('is_guest') ?? false;

    if (isGuest) {
      DashboardStateNotifier.updateUser({
        'full_name': 'Guest User',
        'email': 'guest@example.com',
        'phone': '',
      });
      DashboardStateNotifier.updateSubscription({
        'plan': 'Guest',
        'is_active': true,
        'sms_limit': 50,
        'sms_used': 0,
        'sms_remaining': 50,
      });
      await _loadAnalytics();
      _checkAutoTriggerStatus();
      setState(() => _isLoading = false);
      return;
    }

    if (token == null) {
      _redirectToLogin();
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/subscription/my-subscription'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final subData = data['data'];
          DashboardStateNotifier.updateSubscription(subData);
          if (subData['requires_upgrade'] == true) {
            _showSubscriptionExpiredDialog();
            setState(() => _isLoading = false);
            return;
          }
        }
      } else if (response.statusCode == 401) {
        _redirectToLogin();
        return;
      } else if (response.statusCode == 403) {
        final data = json.decode(response.body);
        if (data['code'] == 'SUBSCRIPTION_EXPIRED') {
          _showSubscriptionExpiredDialog();
          setState(() => _isLoading = false);
          return;
        }
        _redirectToLogin();
        return;
      }
    } catch (_) {}

    await _loadUserProfile();
    _checkAutoTriggerStatus();
    await _loadAnalytics();
    setState(() => _isLoading = false);
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final isGuest = prefs.getBool('is_guest') ?? false;
    if (isGuest || token == null) return;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          DashboardStateNotifier.updateUser(data['data']);
          await prefs.setString('user_email', data['data']['email'] ?? '');
          await prefs.setString('user_name', data['data']['full_name'] ?? '');
          await prefs.setString('user_phone', data['data']['phone'] ?? '');
        }
      } else if (response.statusCode == 401) {
        _redirectToLogin();
      }
    } catch (_) {}
  }

  Future<void> _loadAnalytics() async {
    final db = await DatabaseService.db;
    try {
      final totalLeads = (await db.query('leads')).length;
      final totalSmsSent = (await db.query('auto_sms_logs')).length;
      final activeRules = (await db.query(
        'auto_sms_rules',
        where: 'is_active = 1',
      )).length;
      final totalTemplates = (await db.query('templates')).length;
      if (mounted) {
        DashboardStateNotifier.updateAnalytics({
          'totalLeads': totalLeads,
          'totalSmsSent': totalSmsSent,
          'activeRules': activeRules,
          'templates': totalTemplates,
        });
      }
    } catch (_) {}
  }

  void _checkAutoTriggerStatus() async {
    final isRunning = await BackgroundServiceManager.isRunning();
    DashboardStateNotifier.updateAutoTriggerStatus(isRunning);
    NotificationService().showPersistentAutoTriggerNotification(isRunning);
  }

  void _toggleAutoTrigger() async {
    final isRunning = DashboardStateNotifier.autoTriggerNotifier.value;
    final prefs = await SharedPreferences.getInstance();
    const platform = MethodChannel('com.example.message_me/settings');

    if (isRunning) {
      await BackgroundServiceManager.stop();
      await prefs.setBool('auto_trigger_enabled', false);
      // ✅ Mark as explicitly disabled by user
      await prefs.setBool('user_disabled_trigger', true);
      await BackgroundServiceManager.syncRulesToNative(enabled: false);
      try {
        await platform.invokeMethod('stopCallDetection');
      } catch (_) {}
      _showSnack('Auto-trigger disabled', Colors.red);
    } else {
      await BackgroundServiceManager.start();
      await prefs.setBool('auto_trigger_enabled', true);
      // ✅ Clear explicit disable flag
      await prefs.setBool('user_disabled_trigger', false);
      await BackgroundServiceManager.syncRulesToNative(enabled: true);
      try {
        await platform.invokeMethod('startCallDetection');
      } catch (_) {}

      // ✅ Also sync via MethodChannel directly
      try {
        final db = await DatabaseService.db;
        String? missedMsg;
        String? incomingMsg;
        String? outgoingMsg;

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
            final templateId = rule['template_id'] as int?;
            if (templateId != null) {
              final templates = await db.query(
                'templates',
                where: 'id = ?',
                whereArgs: [templateId],
              );
              if (templates.isNotEmpty) {
                message = templates.first['message'] as String? ?? '';
              }
            }
          }

          if (message.isNotEmpty) {
            if (callType == 'missed') missedMsg = message;
            if (callType == 'incoming') incomingMsg = message;
            if (callType == 'outgoing') outgoingMsg = message;
          }
        }

        await platform.invokeMethod('syncRules', {
          'enabled': true,
          'missed': missedMsg,
          'incoming': incomingMsg,
          'outgoing': outgoingMsg,
        });
        debugPrint('✅ syncRules called with enabled: true');
      } catch (e) {
        debugPrint('syncRules error: $e');
      }

      _showSnack('Auto-trigger enabled', Colors.green);
    }

    await Future.delayed(const Duration(milliseconds: 500));
    _checkAutoTriggerStatus();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _redirectToLogin() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  void _showSubscriptionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('Subscription expired'),
          ],
        ),
        content: const Text(
          'Your subscription has expired. Please upgrade to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _redirectToLogin();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ── Navigation ───────────────────────────────────────────────────

  void _navigate(String title) {
    Widget screen;
    if (title == 'incoming') {
      screen = const StatusScreen(type: 'incoming');
    } else if (title == 'outgoing')
      screen = const StatusScreen(type: 'outgoing');
    else if (title == 'missed')
      screen = const StatusScreen(type: 'missed');
    else if (title == 'bulk')
      screen = const BulkSmsScreen();
    else if (title == 'library')
      screen = const MessageLibraryScreen();
    else if (title == 'settings')
      screen = const SettingsScreen();
    else if (title == 'auto')
      screen = const AutoSmsScreen();
    else if (title == 'anyone')
      screen = const SmsAnyoneScreen();
    else if (title == 'block')
      screen = const BlockListScreen();
    else
      return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ValueListenableBuilder(
        valueListenable: DashboardStateNotifier.dashboardNotifier,
        builder: (context, index, _) => IndexedStack(
          index: index,
          children: [
            _buildDashboardPage(),
            _buildAnalyticsPage(),
            _buildQuickActionsPage(),
            _buildProfilePage(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return ValueListenableBuilder(
      valueListenable: DashboardStateNotifier.dashboardNotifier,
      builder: (context, index, _) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: index,
          onTap: DashboardStateNotifier.updateIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: _primary,
          unselectedItemColor: Colors.grey.shade400,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.flash_on_rounded),
              label: 'Actions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  // ── Dashboard page ───────────────────────────────────────────────

  Widget _buildDashboardPage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        color: _primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBanner(),
              const SizedBox(height: 20),
              _buildQuickActionsRow(),
              const SizedBox(height: 20),
              _buildOverviewSection(),
              const SizedBox(height: 20),
              _buildFeaturesGrid(),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            'Manage campaigns, leads and messages',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.normal,
              color: Colors.white70,
            ),
          ),
        ],
      ),
      actions: [
        ValueListenableBuilder(
          valueListenable: NotificationService().unreadCountNotifier,
          builder: (context, count, _) => Stack(
            children: [
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                ),
                icon: const Icon(Icons.notifications_none_rounded, size: 22),
              ),
              if (count > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.sms_rounded, size: 16, color: Colors.white70),
              SizedBox(width: 10),
              Text(
                'Quick access to all features',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Status banner ────────────────────────────────────────────────

  Widget _buildStatusBanner() {
    return ValueListenableBuilder(
      valueListenable: DashboardStateNotifier.autoTriggerNotifier,
      builder: (context, isRunning, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isRunning ? const Color(0xFF5B67F1) : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRunning
                    ? const Color(0xFF4ADE80)
                    : Colors.red.shade300,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isRunning
                    ? 'Auto-trigger active — monitoring calls'
                    : 'Auto-trigger off — no automatic SMS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GestureDetector(
              onTap: _toggleAutoTrigger,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isRunning ? 'Stop' : 'Start',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick actions row ────────────────────────────────────────────

  Widget _buildQuickActionsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick actions',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _QuickBtn(
              icon: Icons.send_rounded,
              label: 'New SMS',
              color: const Color(0xFF5B67F1),
              bg: const Color(0xFFEEEDFE),
              onTap: () => _navigate('anyone'),
            ),
            const SizedBox(width: 10),
            _QuickBtn(
              icon: Icons.add_rounded,
              label: 'Add rule',
              color: const Color(0xFF5B67F1),
              bg: const Color(0xFFEEEDFE),
              onTap: () => _navigate('auto'),
            ),
            const SizedBox(width: 10),
            _QuickBtn(
              icon: Icons.refresh_rounded,
              label: 'Sync',
              color: const Color(0xFF5B67F1),
              bg: const Color(0xFFEEEDFE),
              onTap: _loadAnalytics,
            ),
            const SizedBox(width: 10),
            _QuickBtn(
              icon: Icons.groups_rounded,
              label: 'Bulk SMS',
              color: const Color(0xFF0F6E56),
              bg: const Color(0xFFE1F5EE),
              onTap: () => _navigate('bulk'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Overview analytics ───────────────────────────────────────────

  Widget _buildOverviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder(
          valueListenable: DashboardStateNotifier.analyticsNotifier,
          builder: (context, a, _) => GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.6,
            children: [
              _AnalyticTile(
                label: 'Total leads',
                value: '${a['totalLeads']}',
                icon: Icons.people_rounded,
                iconBg: const Color(0xFFEEEDFE),
                iconColor: const Color(0xFF534AB7),
              ),
              _AnalyticTile(
                label: 'SMS sent',
                value: '${a['totalSmsSent']}',
                icon: Icons.message_rounded,
                iconBg: const Color(0xFFE1F5EE),
                iconColor: const Color(0xFF0F6E56),
              ),
              _AnalyticTile(
                label: 'Active rules',
                value: '${a['activeRules']}',
                icon: Icons.auto_awesome_rounded,
                iconBg: const Color(0xFFFAEEDA),
                iconColor: const Color(0xFF854F0B),
              ),
              _AnalyticTile(
                label: 'Templates',
                value: '${a['templates']}',
                icon: Icons.library_books_rounded,
                iconBg: const Color(0xFFEEEDFE),
                iconColor: const Color(0xFF534AB7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Features grid ────────────────────────────────────────────────

  Widget _buildFeaturesGrid() {
    final features = [
      _FeatureItem(
        'Auto SMS',
        Icons.auto_awesome_rounded,
        const Color(0xFFEEEDFE),
        const Color(0xFF534AB7),
        'auto',
      ),
      _FeatureItem(
        'SMS anyone',
        Icons.send_rounded,
        const Color(0xFFF3EEFF),
        const Color(0xFF7F77DD),
        'anyone',
      ),
      _FeatureItem(
        'Message library',
        Icons.library_books_rounded,
        const Color(0xFFEAF3DE),
        const Color(0xFF3B6D11),
        'library',
      ),
      _FeatureItem(
        'Block list',
        Icons.block_rounded,
        const Color(0xFFFCEBEB),
        const Color(0xFFA32D2D),
        'block',
      ),
      _FeatureItem(
        'Bulk SMS',
        Icons.groups_rounded,
        const Color(0xFFE1F5EE),
        const Color(0xFF0F6E56),
        'bulk',
      ),
      _FeatureItem(
        'Settings',
        Icons.settings_rounded,
        const Color(0xFFF1EFE8),
        const Color(0xFF5F5E5A),
        'settings',
      ),
      _FeatureItem(
        'Incoming',
        Icons.call_received_rounded,
        const Color(0xFFEAF3DE),
        const Color(0xFF3B6D11),
        'incoming',
      ),
      _FeatureItem(
        'Outgoing',
        Icons.call_made_rounded,
        const Color(0xFFE6F1FB),
        const Color(0xFF185FA5),
        'outgoing',
      ),
      _FeatureItem(
        'Missed',
        Icons.call_missed_rounded,
        const Color(0xFFFCEBEB),
        const Color(0xFFA32D2D),
        'missed',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Features',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: features.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, i) {
            final f = features[i];
            return GestureDetector(
              onTap: () => _navigate(f.key),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: f.iconBg, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: f.iconBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(f.icon, color: f.iconColor, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      f.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Analytics page ───────────────────────────────────────────────

  Widget _buildAnalyticsPage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Analytics',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        color: _primary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [_buildDetailedAnalytics()]),
        ),
      ),
    );
  }

  Widget _buildDetailedAnalytics() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF534AB7),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Detailed statistics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder(
            valueListenable: DashboardStateNotifier.analyticsNotifier,
            builder: (context, a, _) => Column(
              children: [
                _StatRow(
                  'Total calls',
                  '${a['totalLeads']}',
                  const Color(0xFF534AB7),
                ),
                _StatRow(
                  'SMS sent',
                  '${a['totalSmsSent']}',
                  const Color(0xFF0F6E56),
                ),
                _StatRow(
                  'Active rules',
                  '${a['activeRules']}',
                  const Color(0xFF854F0B),
                ),
                _StatRow(
                  'Templates',
                  '${a['templates']}',
                  const Color(0xFF534AB7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _StatRow(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick actions page ───────────────────────────────────────────

  Widget _buildQuickActionsPage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Quick actions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            children: [
              _ActionTile(
                Icons.send_rounded,
                'Send new SMS',
                'Compose and send instantly',
                () => _navigate('anyone'),
              ),
              _ActionTile(
                Icons.add_rounded,
                'Create auto rule',
                'Set up automated SMS triggers',
                () => _navigate('auto'),
              ),
              _ActionTile(
                Icons.library_books_rounded,
                'Manage templates',
                'Create and edit message templates',
                () => _navigate('library'),
              ),
              _ActionTile(
                Icons.refresh_rounded,
                'Sync data',
                'Refresh leads and analytics',
                _loadAnalytics,
              ),
              ValueListenableBuilder(
                valueListenable: DashboardStateNotifier.autoTriggerNotifier,
                builder: (context, isRunning, _) => _ActionTile(
                  isRunning
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  isRunning ? 'Stop auto-trigger' : 'Start auto-trigger',
                  isRunning
                      ? 'Disable automatic SMS'
                      : 'Enable automatic SMS on calls',
                  _toggleAutoTrigger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ActionTile(
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEDFE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF534AB7), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        sub,
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
    );
  }

  // ── Profile page ─────────────────────────────────────────────────

  Widget _buildProfilePage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserProfile,
        color: _primary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProfileCard(),
              const SizedBox(height: 14),
              _buildSubscriptionCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFEEEDFE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 36,
              color: Color(0xFF534AB7),
            ),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder(
            valueListenable: DashboardStateNotifier.userNotifier,
            builder: (context, user, _) => Column(
              children: [
                Text(
                  user['full_name'] ?? 'User',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user['email'] ?? '',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if ((user['phone'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    user['phone'],
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Guest banner
          ValueListenableBuilder(
            valueListenable: DashboardStateNotifier.subscriptionNotifier,
            builder: (context, sub, _) {
              if (sub['plan'] != 'Guest') return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Create an account to unlock all features',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _performLogout,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Sign up',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),
          _ProfileTile(
            Icons.settings_rounded,
            'App settings',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          _ProfileTile(
            Icons.block_rounded,
            'Block list',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BlockListScreen()),
            ),
          ),
          _ProfileTile(Icons.info_rounded, 'About app', _showAboutDialog),
          _ProfileTile(Icons.share_rounded, 'Share app', _showShareDialog),
          const Divider(),
          _ProfileTile(
            Icons.logout_rounded,
            'Logout',
            _showLogoutDialog,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _ProfileTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red : const Color(0xFF5B67F1);
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : const Color(0xFF1E293B),
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isDestructive ? Colors.red.shade300 : Colors.grey.shade400,
        size: 18,
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.subscriptions_rounded,
                  color: Color(0xFF534AB7),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Subscription',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: DashboardStateNotifier.subscriptionNotifier,
            builder: (context, sub, _) => Column(
              children: [
                _SubRow(
                  'Plan',
                  sub['plan'] ?? 'Free Trial',
                  Icons.star_rounded,
                ),
                _SubRow(
                  'Status',
                  sub['is_active'] == true ? 'Active' : 'Inactive',
                  Icons.circle_rounded,
                  valueColor: sub['is_active'] == true
                      ? Colors.green
                      : Colors.red,
                ),
                if (sub['expiry_date'] != null)
                  _SubRow(
                    'Expiry',
                    _formatDate(sub['expiry_date']),
                    Icons.calendar_today_rounded,
                  ),
                if (sub['days_remaining'] != null)
                  _SubRow(
                    'Days remaining',
                    '${sub['days_remaining']} days',
                    Icons.timer_rounded,
                  ),
                _SubRow(
                  'SMS limit',
                  '${sub['sms_limit'] ?? 0}',
                  Icons.message_rounded,
                ),
                _SubRow(
                  'SMS used',
                  '${sub['sms_used'] ?? 0}',
                  Icons.send_rounded,
                ),
                _SubRow(
                  'SMS remaining',
                  '${sub['sms_remaining'] ?? 0}',
                  Icons.rocket_rounded,
                  valueColor: (sub['sms_remaining'] ?? 0) < 100
                      ? Colors.orange
                      : Colors.green,
                ),
                if (sub['plan'] != 'Guest') ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showSnack('Upgrade coming soon!', _primary),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('Upgrade plan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _SubRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEDFE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF534AB7), size: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? d) {
    if (d == null) return 'N/A';
    try {
      final date = DateTime.parse(d);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return d;
    }
  }

  // ── Dialogs ──────────────────────────────────────────────────────

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Logout',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Are you sure you want to logout?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  void _showShareDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Share app'),
        content: const Text('Share SMS Marketing with friends and colleagues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnack('Share feature coming soon!', _primary);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'SMS Marketing',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.sms_rounded, size: 40, color: _primary),
      children: const [
        SizedBox(height: 12),
        Text('A powerful SMS marketing automation tool.'),
      ],
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _QuickBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bg, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  const _AnalyticTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // ✅ don't expand beyond content
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18, // ✅ reduced from 20
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                    height: 1.1, // ✅ tighter line height
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                    height: 1.2, // ✅ tighter line height
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem {
  final String label;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String key;
  _FeatureItem(this.label, this.icon, this.iconBg, this.iconColor, this.key);
}
