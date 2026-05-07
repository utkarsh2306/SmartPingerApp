import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_detection_service.dart';

class WhatsAppService {
  // Send message via WhatsApp (only if installed)
  static Future<bool> sendWhatsApp(String phoneNumber, String message) async {
    if (!await AppDetectionService.isWhatsAppInstalled()) {
      return false;
    }

    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!cleanNumber.startsWith('+')) {
      cleanNumber = '+91$cleanNumber';
    }

    String encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = Uri.parse(
      'whatsapp://send?phone=$cleanNumber&text=$encodedMessage',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error opening WhatsApp: $e');
      return false;
    }
  }
}

// Multi-App Messaging Service - Shows only installed apps
class MultiAppMessagingService {
  static Future<void> sendMessage({
    required BuildContext context,
    required String phoneNumber,
    required String message,
  }) async {
    // Get only available apps
    final availableApps = await AppDetectionService.getAvailableApps();

    if (availableApps.isEmpty) {
      _showNoAppsDialog(context);
      return;
    }

    // Show bottom sheet with only available apps
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Choose App to Send Message',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              ...availableApps.map(
                (app) => _AppOption(
                  icon: app.icon,
                  title: app.name,
                  color: app.color,
                  onTap: () async {
                    Navigator.pop(context);
                    final success = await app.launch(phoneNumber, message);
                    if (context.mounted && !success) {
                      _showFailedDialog(context, app.name);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static void _showNoAppsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('No Messaging Apps'),
        content: const Text('No messaging apps are installed on your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showFailedDialog(BuildContext context, String appName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cannot Open $appName'),
        content: Text('Unable to open $appName. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// App Option Widget
class _AppOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _AppOption({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
    );
  }
}
