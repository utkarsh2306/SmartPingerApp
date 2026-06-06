import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/service/admin_notification_service.dart';
import 'package:message_me/service/background_service.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/notification_service.dart';
import 'package:message_me/service/permission_service.dart';
import 'package:message_me/service/crash_reporter.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<Offset> _slide;
  String _status = 'Initializing...';

  static const _primary = Color(0xFF5B67F1);
  static const _green = Color(0xFF22C55E);
  static const _bg = Color(0xFF0D0F18);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.elasticOut)),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic)),
    );
    _ctrl.forward();
    // ✅ Init everything AFTER UI shows
    _initAndNavigate();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _initAndNavigate() async {
    // ✅ Show splash for min 2 seconds so logo animation completes
    final minWait = Future.delayed(const Duration(milliseconds: 2000));

    // ✅ Run all heavy init in parallel
    await Future.wait([
      minWait,
      _doInit(),
    ]);

    if (!mounted) return;
    _navigate();
  }

  Future<void> _doInit() async {
    // Request permissions (non-blocking — won't crash if denied)
    await CrashReporter.wrap(
      () => PermissionService.request(),
      context: 'PermissionService.request',
    );
    _setStatus('Setting up database...');

    // Init database
    await CrashReporter.wrap(
      () => DatabaseService.db,
      context: 'DatabaseService.db',
    );
    _setStatus('Starting background service...');

    // ✅ Only start background service if user is logged in
    await CrashReporter.wrap(() async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final isLoggedIn = token != null && token.isNotEmpty;

      if (!isLoggedIn) {
        // Not logged in — ensure everything is disabled
        await prefs.setBool('auto_trigger_enabled', false);
        await prefs.setBool('user_disabled_trigger', false);
        await BackgroundServiceManager.syncRulesToNative(enabled: false);
        // Don't start service at all
        return;
      }

      // Logged in — initialize and conditionally start
      await BackgroundServiceManager.initialize();
      await BackgroundServiceManager.start();

      final explicitlyDisabled = prefs.getBool('user_disabled_trigger') ?? false;
      if (!explicitlyDisabled) {
        await prefs.setBool('auto_trigger_enabled', true);
      }
      final wasEnabled = prefs.getBool('auto_trigger_enabled') ?? false;
      await BackgroundServiceManager.syncRulesToNative(enabled: wasEnabled);
    }, context: 'auto-trigger-sync');

    // Init notifications
    await CrashReporter.wrap(
      () => NotificationService().initTable(),
      context: 'NotificationService.initTable',
    );

    // ✅ Fetch admin-sent notifications from server
    await CrashReporter.wrap(
      () => AdminNotificationService().fetchAndStore(),
      context: 'AdminNotificationService.fetchAndStore',
    );

    _setStatus('Ready!');
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  void _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => (token != null && token.isNotEmpty)
            ? const DashboardScreen()
            : const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Dot grid background
          Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
          // Ambient glow
          Positioned(top: -100, left: -100,
            child: _blob(350, _primary.withOpacity(0.12))),
          Positioned(bottom: -80, right: -80,
            child: _blob(280, _green.withOpacity(0.08))),
          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                ScaleTransition(
                  scale: _scale,
                  child: FadeTransition(
                    opacity: _fade,
                    child: _buildLogo(),
                  ),
                ),
                const SizedBox(height: 28),
                // App name
                SlideTransition(
                  position: _slide,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Column(children: [
                      RichText(text: const TextSpan(
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1),
                        children: [
                          TextSpan(text: 'Smart ', style: TextStyle(color: Colors.white)),
                          TextSpan(text: 'Pinger', style: TextStyle(color: _primary)),
                        ],
                      )),
                      const SizedBox(height: 8),
                      const Text(
                        'Auto SMS on every call',
                        style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w400),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 64),
                // Loading indicator
                FadeTransition(
                  opacity: _fade,
                  child: _LoadingDots(),
                ),
              ],
            ),
          ),
          // Bottom branding
          Positioned(bottom: 40, left: 0, right: 0,
            child: FadeTransition(
              opacity: _fade,
              child: const Column(children: [
                Text('by Nextracom Pvt Ltd',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
                SizedBox(height: 4),
                Text('nextracom.in',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white12, fontSize: 10)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 96, height: 96,
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(
          color: _primary.withOpacity(0.5),
          blurRadius: 32, offset: const Offset(0, 12),
        )],
      ),
      child: Stack(alignment: Alignment.center, children: [
        const Icon(Icons.sms_rounded, color: Colors.white, size: 48),
        Positioned(bottom: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _green, shape: BoxShape.circle,
              border: Border.all(color: _bg, width: 2),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 10),
          ),
        ),
      ]),
    );
  }

  Widget _blob(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: color, shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color, blurRadius: 80)],
    ),
  );
}

// ── Loading dots ──────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}
class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _c, builder: (_, __) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final delay = i * 0.3;
        final t = (_c.value - delay).clamp(0.0, 1.0);
        final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 6, height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF5B67F1).withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        );
      }),
    ));
  }
}

// ── Dot grid ──────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.025);
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}
