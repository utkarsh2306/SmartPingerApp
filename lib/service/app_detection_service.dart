import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppDetectionService {
  // Check if WhatsApp is installed
  static Future<bool> isWhatsAppInstalled() async {
    // ✅ wa.me always works — no need to check package visibility
    return true;
  }

  // Check if Telegram is installed
  static Future<bool> isTelegramInstalled() async {
    final telegramUrl = Uri.parse('tg://resolve');
    try {
      return await canLaunchUrl(telegramUrl);
    } catch (e) {
      return false;
    }
  }

  // Check if Messenger is installed
  static Future<bool> isMessengerInstalled() async {
    final messengerUrl = Uri.parse('fb-messenger://');
    try {
      return await canLaunchUrl(messengerUrl);
    } catch (e) {
      return false;
    }
  }

  // Check if WeChat is installed
  static Future<bool> isWeChatInstalled() async {
    final wechatUrl = Uri.parse('weixin://');
    try {
      return await canLaunchUrl(wechatUrl);
    } catch (e) {
      return false;
    }
  }

  // Check if Instagram is installed
  static Future<bool> isInstagramInstalled() async {
    final instagramUrl = Uri.parse('instagram://');
    try {
      return await canLaunchUrl(instagramUrl);
    } catch (e) {
      return false;
    }
  }

  // Check if Viber is installed
  static Future<bool> isViberInstalled() async {
    final viberUrl = Uri.parse('viber://');
    try {
      return await canLaunchUrl(viberUrl);
    } catch (e) {
      return false;
    }
  }

  // Check if Signal is installed
  static Future<bool> isSignalInstalled() async {
    final signalUrl = Uri.parse('sgnl://');
    try {
      return await canLaunchUrl(signalUrl);
    } catch (e) {
      return false;
    }
  }

  // Get all available messaging apps
  static Future<List<AvailableApp>> getAvailableApps() async {
    final apps = <AvailableApp>[];

    // SMS always available
    apps.add(
      AvailableApp(
        id: 'sms',
        name: 'SMS',
        icon: Icons.message_rounded,
        color: Colors.green,
        isAvailable: true,
        launch: (phone, message) async {
          final url = Uri.parse(
            'sms:$phone?body=${Uri.encodeComponent(message)}',
          );
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
            return true;
          }
          return false;
        },
      ),
    );

    // Check WhatsApp
    if (await isWhatsAppInstalled()) {
      apps.add(
        AvailableApp(
          id: 'whatsapp',
          name: 'WhatsApp',
          icon: Icons.chat_rounded,
          color: const Color(0xFF25D366),
          isAvailable: true,
          launch: (phone, message) async {
            String cleanNumber = phone.replaceAll(RegExp(r'[^0-9]'), '');
            if (cleanNumber.startsWith('91') && cleanNumber.length > 10) {
              cleanNumber = cleanNumber.substring(2);
            }
            cleanNumber = '91$cleanNumber';
            final url = Uri.parse(
              'https://wa.me/$cleanNumber?text=${Uri.encodeComponent(message)}',
            );
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
              return true;
            }
            return false;
          },
        ),
      );
    }

    // Check Telegram
    if (await isTelegramInstalled()) {
      apps.add(
        AvailableApp(
          id: 'telegram',
          name: 'Telegram',
          icon: Icons.telegram,
          color: const Color(0xFF0088cc),
          isAvailable: true,
          launch: (phone, message) async {
            String cleanNumber = phone.replaceAll(RegExp(r'[^0-9]'), '');
            final url = Uri.parse(
              'tg://send?phone=$cleanNumber&text=${Uri.encodeComponent(message)}',
            );
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
              return true;
            }
            return false;
          },
        ),
      );
    }

    // Check Messenger
    if (await isMessengerInstalled()) {
      apps.add(
        AvailableApp(
          id: 'messenger',
          name: 'Messenger',
          icon: Icons.messenger_rounded,
          color: const Color(0xFF006AFF),
          isAvailable: true,
          launch: (phone, message) async {
            final url = Uri.parse(
              'fb-messenger://share?text=${Uri.encodeComponent(message)}',
            );
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
              return true;
            }
            return false;
          },
        ),
      );
    }

    // Check WeChat
    if (await isWeChatInstalled()) {
      apps.add(
        AvailableApp(
          id: 'wechat',
          name: 'WeChat',
          icon: Icons.wechat,
          color: const Color(0xFF07C160),
          isAvailable: true,
          launch: (phone, message) async {
            final url = Uri.parse('weixin://');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
              return true;
            }
            return false;
          },
        ),
      );
    }

    // Check Viber
    if (await isViberInstalled()) {
      apps.add(
        AvailableApp(
          id: 'viber',
          name: 'Viber',
          icon: Icons.phone_android_rounded,
          color: const Color(0xFF7360F2),
          isAvailable: true,
          launch: (phone, message) async {
            String cleanNumber = phone.replaceAll(RegExp(r'[^0-9]'), '');
            final url = Uri.parse('viber://chat?number=$cleanNumber');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
              return true;
            }
            return false;
          },
        ),
      );
    }

    // Check Signal
    if (await isSignalInstalled()) {
      apps.add(
        AvailableApp(
          id: 'signal',
          name: 'Signal',
          icon: Icons.lock_rounded,
          color: const Color(0xFF3A76F0),
          isAvailable: true,
          launch: (phone, message) async {
            final url = Uri.parse('sgnl://');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
              return true;
            }
            return false;
          },
        ),
      );
    }

    return apps;
  }
}

// Available App Model
class AvailableApp {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final bool isAvailable;
  final Future<bool> Function(String phone, String message) launch;

  AvailableApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.isAvailable,
    required this.launch,
  });
}
