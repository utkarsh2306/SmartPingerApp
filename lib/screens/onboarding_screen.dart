import 'package:flutter/material.dart';
import 'package:message_me/screens/PermissionSetupScreen.dart';
import 'package:message_me/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final bool fromSettings;
  const OnboardingScreen({super.key, this.fromSettings = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _ctrl = PageController();
  int _current = 0;

  static const _primary = Color(0xFF5B67F1);

  final List<_OnboardPage> pages = [
    _OnboardPage(
      icon: Icons.sms_rounded,
      color: Color(0xFF5B67F1),
      title: 'Welcome to Smart Pinger',
      subtitle:
          'Automatically send SMS to anyone who calls you — even when your phone is locked or the app is closed.',
      steps: [],
    ),
    _OnboardPage(
      icon: Icons.security_rounded,
      color: Color(0xFF22C55E),
      title: 'Step 1 — Grant permissions',
      subtitle: 'The app needs a few permissions to work properly.',
      steps: [
        _Step(
          icon: Icons.phone_in_talk_rounded,
          label: 'Call logs access',
          desc: 'To detect incoming, outgoing and missed calls',
        ),
        _Step(
          icon: Icons.sms_rounded,
          label: 'SMS permission',
          desc: 'To send automated messages from your device',
        ),
        _Step(
          icon: Icons.notifications_rounded,
          label: 'Notifications',
          desc: 'To show you when an SMS has been sent',
        ),
      ],
    ),
    _OnboardPage(
      icon: Icons.bolt_rounded,
      color: Color(0xFFF59E0B),
      title: 'Step 2 — Create an auto rule',
      subtitle: 'Tell the app when to send SMS and what message to use.',
      steps: [
        _Step(
          icon: Icons.touch_app_rounded,
          label: 'Tap "Auto SMS" on the dashboard',
          desc: '',
        ),
        _Step(icon: Icons.add_rounded, label: 'Tap "Add rule"', desc: ''),
        _Step(
          icon: Icons.bolt_rounded,
          label: 'Choose trigger',
          desc: 'Missed call, incoming call, or outgoing call',
        ),
        _Step(
          icon: Icons.schedule_rounded,
          label: 'Set delay',
          desc: 'Send immediately or after a few minutes',
        ),
        _Step(
          icon: Icons.message_rounded,
          label: 'Pick a template or write a custom message',
          desc: '',
        ),
        _Step(
          icon: Icons.check_circle_rounded,
          label: 'Save and toggle the rule ON',
          desc: '',
        ),
      ],
    ),
    _OnboardPage(
      icon: Icons.play_circle_filled_rounded,
      color: Color(0xFF5B67F1),
      title: 'Step 3 — Start the service',
      subtitle:
          'The background service keeps everything running even when the app is closed.',
      steps: [
        _Step(
          icon: Icons.dashboard_rounded,
          label: 'Go to Dashboard',
          desc: '',
        ),
        _Step(
          icon: Icons.play_arrow_rounded,
          label: 'Tap "Start" in the status banner',
          desc: 'You\'ll see a notification appear — that means it\'s active',
        ),
        _Step(
          icon: Icons.notifications_active_rounded,
          label: 'Keep the notification visible',
          desc: 'Dismissing it stops the service',
        ),
      ],
    ),
    _OnboardPage(
      icon: Icons.battery_alert_rounded,
      color: Color(0xFFEF4444),
      title: 'Step 4 — Allow background activity',
      subtitle:
          'On most Android phones, you must disable battery optimisation for the app to keep running.',
      steps: [
        _Step(
          icon: Icons.settings_rounded,
          label: 'Open phone Settings',
          desc: '',
        ),
        _Step(
          icon: Icons.apps_rounded,
          label: 'Go to Apps → Smart Pinger',
          desc: '',
        ),
        _Step(
          icon: Icons.battery_charging_full_rounded,
          label: 'Tap Battery → select Unrestricted',
          desc: 'Also called "Allow background activity" on some phones',
        ),
        _Step(
          icon: Icons.info_rounded,
          label: 'Xiaomi / OPPO / Samsung users',
          desc: 'Also disable "Auto-start manager" restrictions for this app',
        ),
      ],
    ),
    _OnboardPage(
      icon: Icons.check_circle_rounded,
      color: Color(0xFF22C55E),
      title: 'You\'re all set!',
      subtitle:
          'Smart Pinger will now automatically send SMS whenever someone calls — no manual effort needed.',
      steps: [
        _Step(
          icon: Icons.call_missed_rounded,
          label: 'Missed call → SMS sent automatically',
          desc: '',
        ),
        _Step(
          icon: Icons.call_received_rounded,
          label: 'Incoming call → SMS sent automatically',
          desc: '',
        ),
        _Step(
          icon: Icons.call_made_rounded,
          label: 'Outgoing call → SMS sent automatically',
          desc: '',
        ),
        _Step(
          icon: Icons.analytics_rounded,
          label: 'Track everything in Analytics',
          desc: 'See all leads and sent messages',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_current < pages.length - 1) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  // Step indicator
                  Row(
                    children: List.generate(
                      pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 6),
                        width: _current == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _current == i
                              ? _primary
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_current < pages.length - 1)
                    TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade500,
                      ),
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),

            // ── Pages ────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _current = i),
                itemCount: pages.length,
                itemBuilder: (_, i) => _buildPage(pages[i]),
              ),
            ),

            // ── Bottom button ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pages[_current].color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _current == pages.length - 1 ? 'Get started' : 'Next',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardPage page) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: page.color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(page.icon, color: page.color, size: 44),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 10),

          // Subtitle
          Text(
            page.subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),

          if (page.steps.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...page.steps.asMap().entries.map(
              (e) => _buildStep(e.key + 1, e.value, page.color),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStep(int num, _Step step, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(child: Icon(step.icon, color: color, size: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (step.desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      height: 1.4,
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
}

class _OnboardPage {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final List<_Step> steps;
  const _OnboardPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.steps,
  });
}

class _Step {
  final IconData icon;
  final String label;
  final String desc;
  const _Step({required this.icon, required this.label, required this.desc});
}
