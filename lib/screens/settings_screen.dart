import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:message_me/service/call_listener_service.dart';
import 'package:message_me/service/permission_service.dart';
import 'package:message_me/service/setting_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool autoSync = true;
  bool sendConfirmation = true;
  bool saveCallLogs = true;
  bool autoTriggerEnabled = true;
  String defaultTemplate = 'Follow-up';
  int daysLimit = 10;

  static const _primary = Color(0xFF5B67F1);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final days = await SettingsService.getDaysLimit();
    setState(() {
      daysLimit = days;
      autoTriggerEnabled = CallListenerService.isRunning();
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Customize your experience',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          children: [
            _Section(
              title: 'Permissions',
              icon: Icons.security_rounded,
              primary: _primary,
              children: [
                _PermissionTile(
                  icon: Icons.phone_in_talk_rounded,
                  color: const Color(0xFF22C55E),
                  title: 'Call logs access',
                  subtitle: 'Needed to detect incoming and missed calls',
                  onCheck: () => PermissionService.request(),
                ),
                const _Divider(),
                _PermissionTile(
                  icon: Icons.sms_rounded,
                  color: const Color(0xFF3B82F6),
                  title: 'SMS permission',
                  subtitle: 'Required to send messages automatically',
                  onCheck: () => PermissionService.request(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _Section(
              title: 'General',
              icon: Icons.tune_rounded,
              primary: _primary,
              children: [
                _SwitchTile(
                  value: autoSync,
                  title: 'Auto-sync call logs',
                  subtitle: 'Sync new calls automatically in background',
                  icon: Icons.sync_rounded,
                  primary: _primary,
                  onChanged: (v) => setState(() => autoSync = v),
                ),
                const _Divider(),
                _SwitchTile(
                  value: sendConfirmation,
                  title: 'SMS confirmation',
                  subtitle: 'Show a success message after sending',
                  icon: Icons.mark_chat_read_rounded,
                  primary: _primary,
                  onChanged: (v) => setState(() => sendConfirmation = v),
                ),
                const _Divider(),
                _SwitchTile(
                  value: saveCallLogs,
                  title: 'Store call history',
                  subtitle: 'Save logs locally for future follow-up',
                  icon: Icons.history_rounded,
                  primary: _primary,
                  onChanged: (v) => setState(() => saveCallLogs = v),
                ),
                const _Divider(),
                _SwitchTile(
                  value: autoTriggerEnabled,
                  title: 'Auto-trigger SMS',
                  subtitle: 'Automatically send SMS when calls are detected',
                  icon: Icons.bolt_rounded,
                  primary: _primary,
                  onChanged: (v) async {
                    setState(() => autoTriggerEnabled = v);
                    if (v) {
                      CallListenerService.startListening();
                      _showSnack('Auto-trigger enabled');
                    } else {
                      CallListenerService.stopListening();
                      _showSnack('Auto-trigger disabled');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            _Section(
              title: 'Display',
              icon: Icons.display_settings_rounded,
              primary: _primary,
              children: [
                _NavTile(
                  icon: Icons.calendar_today_rounded,
                  title: 'Days limit',
                  subtitle: 'Showing last $daysLimit days',
                  primary: _primary,
                  onTap: _showDaysLimitSheet,
                ),
                const _Divider(),
                _NavTile(
                  icon: Icons.dark_mode_rounded,
                  title: 'Theme',
                  subtitle: 'Light mode',
                  primary: _primary,
                  onTap: () => _showSnack('Theme settings coming soon'),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _Section(
              title: 'SIM settings',
              icon: Icons.sim_card_rounded,
              primary: _primary,
              children: [_SimTile(primary: _primary, onOpen: _openSimSettings)],
            ),
            const SizedBox(height: 14),

            _Section(
              title: 'Default template',
              icon: Icons.message_rounded,
              primary: _primary,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select the default SMS template',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: defaultTemplate,
                          borderRadius: BorderRadius.circular(14),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.textsms_rounded),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Follow-up',
                              child: Text('Follow-up template'),
                            ),
                            DropdownMenuItem(
                              value: 'Welcome',
                              child: Text('Welcome message'),
                            ),
                            DropdownMenuItem(
                              value: 'Promotional',
                              child: Text('Promotional offer'),
                            ),
                            DropdownMenuItem(
                              value: 'Service',
                              child: Text('Service update'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => defaultTemplate = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _Section(
              title: 'About',
              icon: Icons.info_outline_rounded,
              primary: _primary,
              children: [
                _NavTile(
                  icon: Icons.rocket_launch_rounded,
                  title: 'Version',
                  subtitle: '1.0.0',
                  primary: _primary,
                  onTap: () {},
                ),
                const _Divider(),
                _NavTile(
                  icon: Icons.person_rounded,
                  title: 'Developer',
                  subtitle: 'SMS Marketing Team',
                  primary: _primary,
                  onTap: () {},
                ),
                const _Divider(),
                _NavTile(
                  icon: Icons.privacy_tip_rounded,
                  title: 'Privacy policy',
                  subtitle: '',
                  primary: _primary,
                  onTap: () => _showSnack('Coming soon'),
                ),
                const _Divider(),
                _NavTile(
                  icon: Icons.description_rounded,
                  title: 'Terms of service',
                  subtitle: '',
                  primary: _primary,
                  onTap: () => _showSnack('Coming soon'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Reset button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showResetSheet,
                icon: const Icon(
                  Icons.restart_alt_rounded,
                  color: Colors.red,
                  size: 18,
                ),
                label: const Text(
                  'Reset to defaults',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Days limit sheet ─────────────────────────────────────────────

  void _showDaysLimitSheet() {
    final options = SettingsService.getDaysOptions();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Days limit',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'How many days of call records to display',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ...options.map(
                (days) => InkWell(
                  onTap: () async {
                    await SettingsService.setDaysLimit(days);
                    setState(() => daysLimit = days);
                    setSheet(() {});
                    Navigator.pop(context);
                    _showSnack('Showing last $days days');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: daysLimit == days
                                  ? _primary
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            color: daysLimit == days
                                ? _primary
                                : Colors.transparent,
                          ),
                          child: daysLimit == days
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 12,
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Last $days days',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: daysLimit == days
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: daysLimit == days
                                ? _primary
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        const Spacer(),
                        if (daysLimit == days)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                fontSize: 11,
                                color: _primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── SIM settings dialog ──────────────────────────────────────────

  void _openSimSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sim_card_rounded,
                color: _primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Change SMS SIM',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'To change your default SMS SIM card:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ...[
              'Open phone Settings',
              'Tap "SIM cards" or "Dual SIM"',
              'Tap "Default for SMS"',
              'Select your preferred SIM',
            ].asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${e.key + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(e.value, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Got it'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        const platform = MethodChannel(
                          'com.example.message_me/settings',
                        );
                        await platform.invokeMethod('openSimSettings');
                      } catch (e) {
                        _showSnack('Could not open SIM settings');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Open settings',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Reset sheet ──────────────────────────────────────────────────

  void _showResetSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.restart_alt_rounded,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Reset all settings?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This will restore all settings back to their default values.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await SettingsService.setDaysLimit(10);
                      setState(() {
                        autoSync = true;
                        sendConfirmation = true;
                        saveCallLogs = true;
                        defaultTemplate = 'Follow-up';
                        daysLimit = 10;
                      });
                      if (autoTriggerEnabled)
                        CallListenerService.startListening();
                      Navigator.pop(context);
                      _showSnack('Settings reset to defaults');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable section widgets ─────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color primary;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.primary,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 56, endIndent: 16);
}

class _SwitchTile extends StatelessWidget {
  final bool value;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color primary;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primary,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: primary, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      activeColor: primary,
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primary;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: primary, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Colors.grey,
        size: 18,
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onCheck;

  const _PermissionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      trailing: TextButton(
        onPressed: onCheck,
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Check',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SimTile extends StatelessWidget {
  final Color primary;
  final VoidCallback onOpen;

  const _SimTile({required this.primary, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.sim_card_rounded, color: primary, size: 18),
      ),
      title: const Text(
        'Default SIM for SMS',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
      subtitle: Text(
        'Change via Android settings',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      trailing: TextButton(
        onPressed: onOpen,
        style: TextButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: primary.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Open',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
