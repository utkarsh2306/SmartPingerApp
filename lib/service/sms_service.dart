import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'package:message_me/service/notification_service.dart';
import 'whatsapp_service.dart';

class SmsService {
  static final Telephony _telephony = Telephony.instance;

  static Future<void> send(String phone, String message) async {
    try {
      await _telephony.sendSms(to: phone, message: message);
    } catch (e) {
      print("SMS failed: $e");
    }
  }

  // New method: Send with app selection
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
    // After sending SMS, add:
    await NotificationService().notifySmsSent(phone, 'Manual SMS');
  }

  // Send via WhatsApp only
  static Future<void> sendViaWhatsApp(String phone, String message) async {
    await WhatsAppService.sendWhatsApp(phone, message);
  }
}
