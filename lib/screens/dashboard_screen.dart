import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:message_me/blocs/dashboard/dashboard_bloc.dart';
import 'package:message_me/screens/auto_sms_screen.dart';
import 'package:message_me/screens/block_list_screen.dart';
import 'package:message_me/screens/bulk_sms_screen.dart';
import 'package:message_me/screens/login_screen.dart';
import 'package:message_me/screens/message_library_screen.dart';
import 'package:message_me/screens/notification_screen.dart';
import 'package:message_me/screens/settings_screen.dart';
import 'package:message_me/screens/sms_anyone_screen.dart';
import 'package:message_me/screens/status_screen.dart';
import 'package:message_me/service/notification_service.dart';
import 'package:message_me/service/background_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _bloc = DashboardBloc();
  static const _primary = Color(0xFF5B67F1);

  @override
  void initState() {
    super.initState();
    _bloc.add(DashboardLoadEvent());
    _bloc.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _bloc.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final s = _bloc.state.value;
    '🔔 State changed: status=${s.status} requiresLogin=${s.requiresLogin} requiresUpgrade=${s.requiresUpgrade} userEmpty=${s.user.isEmpty}';
    if (s.requiresLogin && mounted) {
      _redirectToLogin();
    }
    if (s.requiresUpgrade && mounted) _showSubscriptionExpiredDialog();
  }

  void _redirectToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showSubscriptionExpiredDialog() {
    final sub = _bloc.state.value.subscription;
    final isInactive = sub['is_active'] == false || sub['is_active'] == 0;
    final title = isInactive ? 'Account deactivated' : 'Subscription expired';
    final message = isInactive
        ? 'Your account has been deactivated. Auto SMS has been stopped. Contact us to reactivate.'
        : 'Your subscription has expired. Auto SMS has been stopped. Contact us to renew.';

    showDialog(
      context: context,
      barrierDismissible: false, // ✅ Cannot be dismissed by tapping outside
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false, // ✅ Cannot be dismissed by back button
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                isInactive ? Icons.block_rounded : Icons.warning_amber_rounded,
                color: Colors.red,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEDFE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_rounded,
                      color: Color(0xFF5B67F1),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contact to renew',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse('tel:9536235656');
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                          child: const Text(
                            '9536235656',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B67F1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _redirectToLogin();
              },
              child: const Text('Logout'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('tel:9536235656');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              icon: const Icon(Icons.phone_rounded, size: 16),
              label: const Text('Call now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B67F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  void _navigate(String title) {
    Widget? screen;
    if (title == 'incoming')
      screen = const StatusScreen(type: 'incoming');
    else if (title == 'outgoing')
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
    if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DashboardState>(
      valueListenable: _bloc.state,
      builder: (context, state, _) {
        // ✅ Only show full loading on FIRST load (no data yet)
        if (state.status == DashboardStatus.loading && state.user.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FB),
            body: Center(child: CircularProgressIndicator(color: _primary)),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          body: IndexedStack(
            index: state.tabIndex,
            children: [
              _buildDashboardPage(state),
              _buildAnalyticsPage(state),
              _buildQuickActionsPage(state),
              _buildProfilePage(state),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(state),
        );
      },
    );
  }

  Widget _buildBottomNav(DashboardState state) {
    return Container(
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
        currentIndex: state.tabIndex,
        onTap: (i) => _bloc.add(DashboardTabChangedEvent(i)),
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
    );
  }

  // ── Dashboard page ────────────────────────────────────────────────
  Widget _buildDashboardPage(DashboardState state) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: () async => _bloc.add(DashboardRefreshAnalyticsEvent()),
        color: _primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBanner(state),
              const SizedBox(height: 14),
              // ✅ Plan expiry card on dashboard
              if (state.subscription.isNotEmpty &&
                  state.subscription['plan'] != 'Guest')
                _buildExpiryBanner(state.subscription),
              const SizedBox(height: 14),
              _buildQuickActionsRow(),
              const SizedBox(height: 20),
              _buildOverviewSection(state),
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

  // ✅ NEW: Plan expiry banner on dashboard
  Widget _buildExpiryBanner(Map<String, dynamic> sub) {
    final expiryStr = sub['expiry_date'] ?? sub['subscription_expiry'];
    if (expiryStr == null) return const SizedBox.shrink();

    DateTime? expiry;
    try {
      expiry = DateTime.parse(expiryStr.toString());
    } catch (_) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final daysLeft = expiry.difference(now).inDays;
    final isExpired = expiry.isBefore(now);
    final isExpiring = !isExpired && daysLeft <= 7;

    Color bgColor, textColor, iconColor;
    IconData icon;
    String message;

    if (isExpired) {
      bgColor = const Color(0xFFFCEBEB);
      textColor = const Color(0xFFA32D2D);
      iconColor = const Color(0xFFA32D2D);
      icon = Icons.warning_rounded;
      message = 'Subscription expired on ${_formatDate(expiryStr.toString())}';
    } else if (isExpiring) {
      bgColor = const Color(0xFFFAEEDA);
      textColor = const Color(0xFF854F0B);
      iconColor = const Color(0xFF854F0B);
      icon = Icons.timer_rounded;
      message =
          '$daysLeft day${daysLeft == 1 ? '' : 's'} left — expires ${_formatDate(expiryStr.toString())}';
    } else {
      bgColor = const Color(0xFFE1F5EE);
      textColor = const Color(0xFF0F6E56);
      iconColor = const Color(0xFF0F6E56);
      icon = Icons.verified_rounded;
      message =
          'Active until ${_formatDate(expiryStr.toString())} · ${sub['plan'] ?? ''}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(DashboardState state) {
    final isRunning = state.autoTriggerActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isRunning ? _primary : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning ? const Color(0xFF4ADE80) : Colors.red.shade300,
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
            onTap: () => _bloc.add(DashboardToggleAutoTriggerEvent()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
    );
  }

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
              color: _primary,
              bg: const Color(0xFFEEEDFE),
              onTap: () => _navigate('anyone'),
            ),
            const SizedBox(width: 10),
            _QuickBtn(
              icon: Icons.add_rounded,
              label: 'Add rule',
              color: _primary,
              bg: const Color(0xFFEEEDFE),
              onTap: () => _navigate('auto'),
            ),
            const SizedBox(width: 10),
            _QuickBtn(
              icon: Icons.refresh_rounded,
              label: 'Sync',
              color: _primary,
              bg: const Color(0xFFEEEDFE),
              onTap: () => _bloc.add(DashboardRefreshAnalyticsEvent()),
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

  Widget _buildOverviewSection(DashboardState state) {
    final a = state.analytics;
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
        GridView.count(
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
      ],
    );
  }

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

  // ── Analytics page ────────────────────────────────────────────────
  Widget _buildAnalyticsPage(DashboardState state) {
    final a = state.analytics;
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
        onRefresh: () async => _bloc.add(DashboardRefreshAnalyticsEvent()),
        color: _primary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
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
        ),
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

  // ── Quick actions page ─────────────────────────────────────────────
  Widget _buildQuickActionsPage(DashboardState state) {
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
                () => _bloc.add(DashboardRefreshAnalyticsEvent()),
              ),
              _ActionTile(
                state.autoTriggerActive
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                state.autoTriggerActive
                    ? 'Stop auto-trigger'
                    : 'Start auto-trigger',
                state.autoTriggerActive
                    ? 'Disable automatic SMS'
                    : 'Enable automatic SMS on calls',
                () => _bloc.add(DashboardToggleAutoTriggerEvent()),
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

  // ── Profile page ───────────────────────────────────────────────────
  Widget _buildProfilePage(DashboardState state) {
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
        onRefresh: () async => _bloc.refreshUserProfile(),
        color: _primary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProfileCard(state),
              const SizedBox(height: 14),
              _buildSubscriptionCard(state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(DashboardState state) {
    final user = state.user;
    final sub = state.subscription;
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
          Text(
            user['full_name'] ?? 'User',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if ((user['email'] ?? '').isNotEmpty)
            Text(
              user['email'],
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          if ((user['phone'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              user['phone'],
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 16),
          if (sub['plan'] == 'Guest')
            Container(
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
    final color = isDestructive ? Colors.red : _primary;
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

  Widget _buildSubscriptionCard(DashboardState state) {
    final sub = state.subscription;
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
          _SubRow('Plan', sub['plan'] ?? 'Free Trial', Icons.star_rounded),
          _SubRow(
            'Status',
            sub['is_active'] == true ? 'Active' : 'Inactive',
            Icons.circle_rounded,
            valueColor: sub['is_active'] == true ? Colors.green : Colors.red,
          ),
          // ✅ Show expiry date
          if (sub['expiry_date'] != null)
            _SubRow(
              'Expiry',
              _formatDate(sub['expiry_date'].toString()),
              Icons.calendar_today_rounded,
            ),
          if (sub['days_remaining'] != null)
            _SubRow(
              'Days remaining',
              '${sub['days_remaining']} days',
              Icons.timer_rounded,
              valueColor: (sub['days_remaining'] as num) <= 7
                  ? Colors.orange
                  : Colors.green,
            ),
          _SubRow(
            'SMS limit',
            '${sub['sms_limit'] ?? 0}',
            Icons.message_rounded,
          ),
          _SubRow('SMS used', '${sub['sms_used'] ?? 0}', Icons.send_rounded),
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
                onPressed: () => _showSnack('Upgrade coming soon!', _primary),
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
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return d;
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────
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
    _bloc.reset();
    // ✅ Explicitly stop service and disable trigger — don't toggle
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_trigger_enabled', false);
    await prefs.setBool('user_disabled_trigger', false);
    await prefs.setBool(
      'user_is_active',
      false,
    ); // ✅ Tell Kotlin user logged out
    await BackgroundServiceManager.stop();
    await BackgroundServiceManager.syncRulesToNative(enabled: false);
    try {
      const platform = MethodChannel('com.nextracom.smartpinger/settings');
      await platform.invokeMethod('stopCallDetection');
      await platform.invokeMethod('syncAutoTrigger', {'enabled': false});
    } catch (_) {}
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
        content: const Text('Share Smart Pinger with friends and colleagues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnack('Share coming soon!', _primary);
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
      applicationName: 'Smart Pinger',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.sms_rounded, size: 40, color: _primary),
      children: const [
        SizedBox(height: 12),
        Text('Auto SMS for every call. Built by Nextracom Pvt Ltd.'),
      ],
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────

class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bg;
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
  final String label, value;
  final IconData icon;
  final Color iconBg, iconColor;
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
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
  final String label, key;
  final IconData icon;
  final Color iconBg, iconColor;
  _FeatureItem(this.label, this.icon, this.iconBg, this.iconColor, this.key);
}
