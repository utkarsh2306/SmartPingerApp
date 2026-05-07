// lib/service/referral_service.dart
// Add this file to your Flutter project

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ReferralService {
  static const _baseUrl =
      'http://your-server.com/api'; // ← change to your server

  // ── Get unique device ID ─────────────────────────────────────────
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId != null) return deviceId;

    // Generate one from device info
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        deviceId = android.id; // Android ID
      } else {
        deviceId = DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (_) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    await prefs.setString('device_id', deviceId!);
    return deviceId;
  }

  // ── Validate code before showing signup form ─────────────────────
  static Future<Map<String, dynamic>?> validateCode(String code) async {
    try {
      final deviceId = await getDeviceId();
      final res = await http.get(
        Uri.parse('$_baseUrl/referral/validate/${code.toUpperCase()}?device_id=$deviceId'),
      );
      final data = json.decode(res.body);
      if (data['success'] == true) return data['data'];
      return null;
    } catch (e) {
      debugPrint('validateCode error: $e');
      return null;
    }
  }

  // ── Apply code after user signs up ───────────────────────────────
  static Future<bool> applyCode(String code, String token) async {
    try {
      final deviceId = await getDeviceId();
      final res = await http.post(
        Uri.parse('$_baseUrl/referral/apply'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'code': code.toUpperCase(),
          'device_id': deviceId,
        }),
      );
      final data = json.decode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('applyCode error: $e');
      return false;
    }
  }
}
