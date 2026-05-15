// lib/core/api_config.dart
// ── Central API configuration ─────────────────────────────────────
// Change baseUrl here to switch between environments

class ApiConfig {
  // ✅ Production VPS
  static const String baseUrl = 'https://api.nextracom.tech';

  // Development (uncomment to use)
  // static const String baseUrl = 'http://10.0.2.2:8080'; // Android emulator
  // static const String baseUrl = 'http://localhost:8080'; // iOS simulator

  // API endpoints
  static const String login           = '$baseUrl/api/auth/login';
  static const String loginEmail      = '$baseUrl/api/auth/login/email';
  static const String loginPhone      = '$baseUrl/api/auth/login/phone';
  static const String register        = '$baseUrl/api/auth/register/email';
  static const String registerPhone   = '$baseUrl/api/auth/register/phone';
  static const String me              = '$baseUrl/api/auth/me';
  static const String changePassword  = '$baseUrl/api/auth/change-password';
  static const String mySubscription  = '$baseUrl/api/subscription/my-subscription';
  static const String canSendSms      = '$baseUrl/api/subscription/can-send-sms';
  static const String validateReferral = '$baseUrl/api/referral/validate';

  // HTTP timeout durations
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
