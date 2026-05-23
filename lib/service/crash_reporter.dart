// lib/service/crash_reporter.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/core/api_config.dart';

class CrashReporter {
  static final CrashReporter _instance = CrashReporter._internal();
  factory CrashReporter() => _instance;
  CrashReporter._internal();

  // ── Initialize global crash handler ──────────────────────────────
  static void initialize() {
    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      CrashReporter().report(
        error: details.exception,
        stackTrace: details.stack,
        context: details.context?.toDescription(),
        fatal: false,
      );
    };

    // Catch async/platform errors not caught by Flutter
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashReporter().report(
        error: error,
        stackTrace: stack,
        context: 'PlatformDispatcher',
        fatal: true,
      );
      return true;
    };

    debugPrint('✅ CrashReporter initialized');
  }

  // ── Report a crash ────────────────────────────────────────────────
  Future<void> report({
    required Object error,
    StackTrace? stackTrace,
    String? context,
    bool fatal = false,
    Map<String, dynamic>? extras,
  }) async {
    try {
      // Don't report in debug mode — just print
      if (kDebugMode) {
        debugPrint('🔴 CRASH [${fatal ? "FATAL" : "ERROR"}]: $error');
        debugPrint('📍 Context: $context');
        if (stackTrace != null) debugPrint('📚 $stackTrace');
        return;
      }

      final deviceInfo = await _getDeviceInfo();
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final token = prefs.getString('token');

      final payload = {
        'type': fatal ? 'fatal' : 'error',
        'error': error.toString(),
        'stack_trace': stackTrace?.toString() ?? '',
        'context': context ?? 'unknown',
        'user_id': userId,
        'device': deviceInfo,
        'extras': extras ?? {},
        'timestamp': DateTime.now().toIso8601String(),
      };

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/crashes'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 5));

    } catch (e) {
      // Never let crash reporter itself crash the app
      debugPrint('CrashReporter failed: $e');
    }
  }

  // ── Wrap any function with crash reporting ────────────────────────
  static Future<T?> wrap<T>(
    Future<T> Function() fn, {
    String? context,
    T? fallback,
  }) async {
    try {
      return await fn();
    } catch (e, stack) {
      CrashReporter().report(error: e, stackTrace: stack, context: context);
      return fallback;
    }
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final android = await deviceInfo.androidInfo;
      PackageInfo? pkg;
      try { pkg = await PackageInfo.fromPlatform(); } catch (_) {}
      return {
        'brand': android.brand,
        'model': android.model,
        'android_version': android.version.release,
        'sdk': android.version.sdkInt,
        'app_version': pkg?.version ?? 'unknown',
        'build_number': pkg?.buildNumber ?? 'unknown',
      };
    } catch (_) {
      return {};
    }
  }
}
