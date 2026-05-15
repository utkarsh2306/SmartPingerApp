import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_detection_service.dart';

class WhatsAppService {
  /// ✅ Fixed: uses https://wa.me/ URL which works on all Android versions
  /// The whatsapp:// scheme is blocked by Android 11+ package visibility rules
  static Future<bool> sendWhatsApp(String phoneNumber, String message) async {
    // Clean the number
    String clean = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.startsWith('+91')) {
      clean = clean.substring(3);
    } else if (clean.startsWith('91') && clean.length > 10) {
      clean = clean.substring(2);
    }
    clean = clean.replaceAll(RegExp(r'^0+'), '');

    // Add country code
    final withCountry = '91$clean';
    final encoded = Uri.encodeComponent(message);

    // ✅ Use wa.me URL — works without WhatsApp being declared in queries
    final waUrl = Uri.parse('https://wa.me/$withCountry?text=$encoded');

    try {
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
        return true;
      }
      // Fallback to whatsapp:// scheme
      final fallback = Uri.parse(
        'whatsapp://send?phone=$withCountry&text=$encoded',
      );
      if (await canLaunchUrl(fallback)) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('WhatsApp error: $e');
      return false;
    }
  }
}

// ── Multi-App Messaging Service ────────────────────────────────────
class MultiAppMessagingService {
  static Future<void> sendMessage({
    required BuildContext context,
    required String phoneNumber,
    required String message,
  }) async {
    final availableApps = await AppDetectionService.getAvailableApps();

    if (availableApps.isEmpty) {
      _showNoAppsDialog(context);
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 48, height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Choose app to send message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...availableApps.map(
              (app) => ListTile(
                onTap: () async {
                  Navigator.pop(ctx);
                  final success = await app.launch(phoneNumber, message);
                  if (ctx.mounted && !success) {
                    _showFailedDialog(ctx, app.name);
                  }
                },
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: app.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(app.icon, color: app.color, size: 26),
                ),
                title: Text(app.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static void _showNoAppsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('No messaging apps'),
        content: const Text('No messaging apps are installed on your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showFailedDialog(BuildContext context, String appName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cannot open $appName'),
        content: Text('Unable to open $appName. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
