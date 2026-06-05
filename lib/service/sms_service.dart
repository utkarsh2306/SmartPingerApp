import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:message_me/service/notification_service.dart';
import 'whatsapp_service.dart';

class SmsService {
  // ✅ SMS sent via native Kotlin SmsManager — no another_telephony
  static const _channel = MethodChannel('com.nextracom.smartpinger/settings');

  static Future<void> send(String phone, String message) async {
    try {
      await _channel.invokeMethod('sendSms', {
        'phone': phone,
        'message': message,
      });
    } catch (e) {
      debugPrint('SMS failed: $e');
    }
  }

  static Future<void> sendWithAppSelection({
    required BuildContext context,
    required String phone,
    required String message,
  }) async {
    await MultiAppMessagingService.sendMessage(
      context: context,
      phoneNumber: phone,
      message: message,
    );
    await NotificationService().notifySmsSent(phone, 'Manual SMS');
  }

  static Future<void> sendViaWhatsApp(String phone, String message) async {
    await WhatsAppService.sendWhatsApp(phone, message);
  }
}
