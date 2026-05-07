import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/screens/dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _referralCtrl = TextEditingController(); // ✅ new

  bool isLoginMode = true;
  bool loading = false;
  bool obscurePassword = true;
  String? _referralError; // ✅ validation state
  bool _referralValid = false;

  late AnimationController _animCtrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _primary = Color(0xFF6366F1);
  static const _accent = Color(0xFF10B981);
  static const _bg = Color(0xFF4F46E5);

  final String baseUrl =
      'http://ec2-65-2-170-60.ap-south-1.compute.amazonaws.com:8080';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _referralCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _getDeviceId() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      return android.id;
    } catch (_) {
      return null;
    }
  }

  // ✅ Validate referral code in real-time
  Future<void> _validateReferral(String code) async {
    if (code.trim().isEmpty) {
      setState(() {
        _referralError = null;
        _referralValid = false;
      });
      return;
    }
    if (code.trim().length < 4) return;

    final deviceId = await _getDeviceId();
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/referral/validate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'code': code.trim().toUpperCase(),
          'device_id': deviceId,
        }),
      );
      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final d = data['data'];
        setState(() {
          _referralError = null;
          _referralValid = true;
        });
        _showSnack(
          '✅ Code valid — ${d['plan']} plan, ${d['duration_days']} days'
          '${d['sms_bonus'] > 0 ? ', +${d['sms_bonus']} SMS bonus' : ''}',
          Colors.green,
        );
      } else {
        setState(() {
          _referralError = data['error'] ?? 'Invalid code';
          _referralValid = false;
        });
      }
    } catch (_) {
      setState(() {
        _referralError = null;
        _referralValid = false;
      });
    }
  }

  // ── Login ──────────────────────────────────────────────────────

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (email.isEmpty) {
      _showSnack('Please enter your email', Colors.red);
      return;
    }
    if (password.isEmpty) {
      _showSnack('Please enter your password', Colors.red);
      return;
    }

    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'identifier': email, 'password': password}),
      );
      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['data']['token']);
        await prefs.setString('user_id', data['data']['user']['id']);
        await prefs.setString(
          'user_email',
          data['data']['user']['email'] ?? '',
        );
        await prefs.setString(
          'user_name',
          data['data']['user']['full_name'] ?? '',
        );
        await prefs.remove('is_guest');
        _showSnack('Login successful!', Colors.green);
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (_) => false,
          );
        }
      } else {
        _showSnack(data['error'] ?? 'Login failed', Colors.red);
      }
    } catch (_) {
      _showSnack('Network error. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ── Signup ─────────────────────────────────────────────────────

  Future<void> _signup() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final fullName = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final referral = _referralCtrl.text.trim().toUpperCase();

    if (fullName.isEmpty) {
      _showSnack('Please enter your full name', Colors.red);
      return;
    }
    if (email.isEmpty) {
      _showSnack('Please enter your email', Colors.red);
      return;
    }
    if (password.isEmpty) {
      _showSnack('Please enter your password', Colors.red);
      return;
    }
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters', Colors.red);
      return;
    }

    final deviceId = await _getDeviceId();

    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/auth/register/email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'full_name': fullName,
          'phone': phone.isNotEmpty ? phone : null,
          // ✅ Send referral code and device ID
          if (referral.isNotEmpty) 'referral_code': referral,
          if (deviceId != null) 'device_id': deviceId,
        }),
      );
      final data = json.decode(res.body);
      if (res.statusCode == 201 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['data']['token']);
        await prefs.setString('user_id', data['data']['user']['id']);
        await prefs.setString(
          'user_email',
          data['data']['user']['email'] ?? '',
        );
        await prefs.setString(
          'user_name',
          data['data']['user']['full_name'] ?? '',
        );
        await prefs.remove('is_guest');
        _showSnack('Account created!', Colors.green);
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (_) => false,
          );
        }
      } else {
        _showSnack(data['error'] ?? 'Signup failed', Colors.red);
      }
    } catch (_) {
      _showSnack('Network error. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _skipLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.remove('token');
    _showSnack('Continuing as guest', Colors.orange);
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    }
  }

  void _toggleMode() {
    setState(() {
      isLoginMode = !isLoginMode;
      _emailCtrl.clear();
      _passwordCtrl.clear();
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _referralCtrl.clear();
      _referralError = null;
      _referralValid = false;
    });
    _animCtrl.reset();
    _animCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [_buildHeader(), _buildFormSheet()]),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.sms_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                    Positioned(
                      bottom: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                isLoginMode ? 'Welcome back' : 'Create account',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isLoginMode ? 'Sign in to continue' : 'Sign up to get started',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSheet() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      child: FadeTransition(
        opacity: _fade,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLoginMode ? 'Sign in' : 'Sign up',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isLoginMode
                  ? 'Enter your credentials to continue'
                  : 'Fill in your details below',
              style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 28),

            if (!isLoginMode) ...[
              _Field(
                label: 'Full name',
                hint: 'John Doe',
                controller: _nameCtrl,
                enabled: !loading,
              ),
              const SizedBox(height: 14),
            ],

            _Field(
              label: 'Email address',
              hint: 'you@example.com',
              controller: _emailCtrl,
              keyboard: TextInputType.emailAddress,
              enabled: !loading,
            ),
            const SizedBox(height: 14),

            _PasswordField(
              controller: _passwordCtrl,
              obscure: obscurePassword,
              enabled: !loading,
              onToggle: () =>
                  setState(() => obscurePassword = !obscurePassword),
            ),
            const SizedBox(height: 14),

            if (!isLoginMode) ...[
              _PhoneField(controller: _phoneCtrl, enabled: !loading),
              const SizedBox(height: 14),

              // ✅ Referral code field
              _ReferralField(
                controller: _referralCtrl,
                enabled: !loading,
                isValid: _referralValid,
                errorText: _referralError,
                onChanged: (v) {
                  setState(() {
                    _referralError = null;
                    _referralValid = false;
                  });
                },
                onSubmitted: (v) => _validateReferral(v),
              ),
              const SizedBox(height: 14),
            ],

            if (isLoginMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      _showSnack('Forgot password coming soon', _primary),
                  style: TextButton.styleFrom(
                    foregroundColor: _primary,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : (isLoginMode ? _login : _signup),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLoginMode ? _primary : _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isLoginMode ? 'Sign in' : 'Create account',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: loading ? null : _skipLogin,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_outline_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Continue as guest',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isLoginMode
                      ? "Don't have an account? "
                      : "Already have an account? ",
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: _toggleMode,
                  child: Text(
                    isLoginMode ? 'Sign up' : 'Sign in',
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  text: 'By continuing, you agree to our ',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                  children: [
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Field widgets ─────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final TextInputType keyboard;
  final bool enabled;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboard = TextInputType.text,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboard,
            enabled: enabled,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFFCBD5E1),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure, enabled;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  enabled: enabled,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0xFFCBD5E1),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggle,
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  const _PhoneField({required this.controller, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone number (optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: const Text(
                  '+91',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  enabled: enabled,
                  maxLength: 10,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '98765 43210',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Color(0xFFCBD5E1),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ✅ New referral code field
class _ReferralField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled, isValid;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _ReferralField({
    required this.controller,
    required this.enabled,
    required this.isValid,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = errorText != null
        ? Colors.red.shade300
        : isValid
        ? Colors.green.shade300
        : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Referral code (optional)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: 0.3,
              ),
            ),
            if (isValid) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green.shade600,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Valid',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: errorText != null || isValid ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: Color(0xFF94A3B8),
                  size: 18,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                    letterSpacing: 1,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter code e.g. SUMMER2026',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.normal,
                      letterSpacing: 0,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                TextButton(
                  onPressed: () => onSubmitted(controller.text),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Colors.red.shade400,
                size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                errorText!,
                style: TextStyle(fontSize: 11, color: Colors.red.shade600),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
