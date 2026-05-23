// lib/core/api_config.dart
class ApiConfig {
  // ✅ Production — change here to switch environments
  static const String baseUrl = 'https://api.nextracom.tech';

  // Development (uncomment to use locally)
  // static const String baseUrl = 'http://10.0.2.2:8080';

  // ── Auth
  static const String login            = '$baseUrl/api/auth/login';
  static const String register         = '$baseUrl/api/auth/register/email';
  static const String me               = '$baseUrl/api/auth/me';
  static const String changePassword   = '$baseUrl/api/auth/change-password';

  // ── Subscription
  static const String mySubscription   = '$baseUrl/api/subscription/my-subscription';
  static const String canSendSms       = '$baseUrl/api/subscription/can-send-sms';

  // ── Referral
  static const String validateReferral = '$baseUrl/api/referral/validate';

  // ── Crash reporting
  static const String crashes          = '$baseUrl/api/crashes';

  // ── Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
