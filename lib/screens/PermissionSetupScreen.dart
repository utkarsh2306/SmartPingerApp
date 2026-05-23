import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/screens/splash_screen.dart';
import 'package:message_me/service/permission_service.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  static const _primary = Color(0xFF5B67F1);

  bool _phoneGranted = false;
  bool _smsGranted = false;
  bool _notificationGranted = false;
  bool _overlayGranted = false;
  bool _batteryGranted = false;

  static const _platform = MethodChannel('com.nextracom.smartpinger/settings');

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final phone = await Permission.phone.isGranted;
    final sms = await Permission.sms.isGranted;
    final notification = await Permission.notification.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlay = await PermissionService.hasOverlayPermission();

    setState(() {
      _phoneGranted = phone;
      _smsGranted = sms;
      _notificationGranted = notification;
      _batteryGranted = battery;
      _overlayGranted = overlay;
    });
  }

  bool get _allGranted =>
      _phoneGranted &&
      _smsGranted &&
      _notificationGranted &&
      _overlayGranted &&
      _batteryGranted;

  Future<void> _requestAll() async {
    await Permission.phone.request();
    await Permission.sms.request();
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
    await _checkPermissions();
  }

  Future<void> _proceed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_setup_done', true);
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'App setup',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: _primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Smart Pinger needs these permissions to send SMS '
                      'automatically even when the app is closed.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Required permissions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),

            _PermissionTile(
              icon: Icons.phone_rounded,
              title: 'Phone & call logs',
              desc: 'Detect incoming, outgoing and missed calls',
              granted: _phoneGranted,
              onTap: () async {
                await Permission.phone.request();
                await _checkPermissions();
              },
            ),
            _PermissionTile(
              icon: Icons.sms_rounded,
              title: 'Send SMS',
              desc: 'Send automated messages from your device',
              granted: _smsGranted,
              onTap: () async {
                await Permission.sms.request();
                await _checkPermissions();
              },
            ),
            _PermissionTile(
              icon: Icons.notifications_rounded,
              title: 'Notifications',
              desc: 'Show alerts when SMS is sent',
              granted: _notificationGranted,
              onTap: () async {
                await Permission.notification.request();
                await _checkPermissions();
              },
            ),

            const SizedBox(height: 20),
            const Text(
              'Background permissions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'These are required for SMS to send when the app is closed.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),

            _PermissionTile(
              icon: Icons.layers_rounded,
              title: 'Display over other apps',
              desc: 'Keeps the app active in background on all devices',
              granted: _overlayGranted,
              important: true,
              onTap: () async {
                await PermissionService.requestOverlayPermission();
                await Future.delayed(const Duration(seconds: 1));
                await _checkPermissions();
              },
            ),
            _PermissionTile(
              icon: Icons.battery_charging_full_rounded,
              title: 'Ignore battery optimization',
              desc: 'Prevents Android from stopping the service',
              granted: _batteryGranted,
              important: true,
              onTap: () async {
                await Permission.ignoreBatteryOptimizations.request();
                await _checkPermissions();
              },
            ),

            const SizedBox(height: 28),

            // Grant all button
            if (!_allGranted)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _requestAll,
                  icon: const Icon(Icons.security_rounded, size: 18),
                  label: const Text('Grant all permissions'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _proceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _allGranted
                      ? _primary
                      : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _allGranted ? 'Continue' : 'Continue anyway',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            if (!_allGranted) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'You can grant permissions later from Settings',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool granted;
  final bool important;
  final VoidCallback onTap;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
    required this.onTap,
    this.important = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted
              ? Colors.green.shade200
              : important
              ? Colors.orange.shade200
              : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: granted
                ? Colors.green.shade50
                : important
                ? Colors.orange.shade50
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: granted
                ? Colors.green
                : important
                ? Colors.orange
                : Colors.grey,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          desc,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: granted
            ? const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 22,
              )
            : TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  backgroundColor: important
                      ? Colors.orange.shade50
                      : const Color(0xFFEEEDFE),
                  foregroundColor: important
                      ? Colors.orange
                      : const Color(0xFF5B67F1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Allow',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
      ),
    );
  }
}
