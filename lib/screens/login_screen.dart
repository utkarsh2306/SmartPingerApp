import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:message_me/core/api_config.dart';
import 'package:message_me/service/crash_reporter.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _referralCtrl = TextEditingController();

  bool _isLoginMode = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _referralError;
  bool _referralValid = false;

  late AnimationController _animCtrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _primary = Color(0xFF5B67F1);
  static const _accent  = Color(0xFF22C55E);
  static const _bg      = Color(0xFF4A56E0);

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 700), vsync: this);
    _fade  = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose(); _passwordCtrl.dispose();
    _nameCtrl.dispose();  _phoneCtrl.dispose();
    _referralCtrl.dispose(); _animCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<String?> _getDeviceId() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      return android.id;
    } catch (_) { return null; }
  }

  // ── Validate referral code ────────────────────────────────────
  Future<void> _validateReferral(String code) async {
    if (code.trim().isEmpty) {
      setState(() { _referralError = null; _referralValid = false; });
      return;
    }
    if (code.trim().length < 4) return;

    final deviceId = await _getDeviceId();
    try {
      final res = await http.post(
        Uri.parse(ApiConfig.validateReferral),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'code': code.trim().toUpperCase(),
          'device_id': deviceId,
        }),
      ).timeout(ApiConfig.connectTimeout);

      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        final d = data['data'];
        setState(() { _referralError = null; _referralValid = true; });
        _snack(
          '✅ Code valid — ${d['plan']} plan, ${d['duration_days']} days'
          '${(d['sms_bonus'] ?? 0) > 0 ? ", +${d['sms_bonus']} SMS bonus" : ""}',
          Colors.green,
        );
      } else {
        setState(() {
          _referralError = data['error'] ?? 'Invalid code';
          _referralValid = false;
        });
      }
    } catch (_) {
      setState(() { _referralError = null; _referralValid = false; });
    }
  }

  // ── Login ─────────────────────────────────────────────────────
  Future<void> _login() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty)    { _snack('Please enter your email', Colors.red); return; }
    if (password.isEmpty) { _snack('Please enter your password', Colors.red); return; }

    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse(ApiConfig.login),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'identifier': email, 'password': password}),
      ).timeout(ApiConfig.receiveTimeout);

      final data = json.decode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        await _saveUserData(data['data']);
        _snack('Welcome back!', Colors.green);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _goToDashboard();
      } else {
        _snack(data['error'] ?? 'Login failed. Please try again.', Colors.red);
      }
    } catch (e, stack) {
      CrashReporter().report(error: e, stackTrace: stack, context: '_login');
      _snack('Network error. Please check your connection.', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Signup ────────────────────────────────────────────────────
  Future<void> _signup() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final fullName = _nameCtrl.text.trim();
    final phone    = _phoneCtrl.text.trim();
    final referral = _referralCtrl.text.trim().toUpperCase();

    if (fullName.isEmpty) { _snack('Please enter your full name', Colors.red); return; }
    if (email.isEmpty)    { _snack('Please enter your email', Colors.red); return; }
    if (password.isEmpty) { _snack('Please enter your password', Colors.red); return; }
    if (password.length < 6) { _snack('Password must be at least 6 characters', Colors.red); return; }

    final deviceId = await _getDeviceId();

    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'full_name': fullName,
        if (phone.isNotEmpty) 'phone': phone,
        // ✅ Referral code and device ID sent to API
        if (referral.isNotEmpty) 'referral_code': referral,
        if (deviceId != null) 'device_id': deviceId,
      };

      final res = await http.post(
        Uri.parse(ApiConfig.register),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(ApiConfig.receiveTimeout);

      final data = json.decode(res.body);
      if (res.statusCode == 201 && data['success'] == true) {
        await _saveUserData(data['data']);
        _snack('Account created! Welcome to Smart Pinger.', _accent);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _goToDashboard();
      } else {
        _snack(data['error'] ?? 'Signup failed. Please try again.', Colors.red);
      }
    } catch (e, stack) {
      CrashReporter().report(error: e, stackTrace: stack, context: '_signup');
      _snack('Network error. Please check your connection.', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveUserData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', data['token'] ?? '');
    await prefs.setString('user_id', data['user']?['id'] ?? '');
    await prefs.setString('user_email', data['user']?['email'] ?? '');
    await prefs.setString('user_name', data['user']?['full_name'] ?? '');
    await prefs.remove('is_guest');
  }

  void _goToDashboard() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (_) => false,
    );
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _emailCtrl.clear(); _passwordCtrl.clear();
      _nameCtrl.clear();  _phoneCtrl.clear();
      _referralCtrl.clear();
      _referralError = null; _referralValid = false;
    });
    _animCtrl.reset(); _animCtrl.forward();
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

  // ── Header ────────────────────────────────────────────────────
  Widget _buildHeader() {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          child: Column(children: [
            // Logo
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
              ),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.sms_rounded, color: Colors.white, size: 44),
                Positioned(bottom: 14, right: 14,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _accent, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Text(
              _isLoginMode ? 'Welcome back' : 'Create account',
              style: const TextStyle(color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
            const SizedBox(height: 6),
            Text(
              _isLoginMode ? 'Sign in to Smart Pinger' : 'Join Smart Pinger today',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
            ),
            const SizedBox(height: 8),
            // Nextracom branding
            Text(
              'by Nextracom Pvt Ltd',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Form sheet ────────────────────────────────────────────────
  Widget _buildFormSheet() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: FadeTransition(
        opacity: _fade,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isLoginMode ? 'Sign in' : 'Sign up',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(
            _isLoginMode ? 'Enter your credentials to continue' : 'Fill in your details below',
            style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 24),

          if (!_isLoginMode) ...[
            _buildField('Full name', 'John Doe', _nameCtrl),
            const SizedBox(height: 12),
          ],

          _buildField('Email address', 'you@example.com', _emailCtrl,
            keyboard: TextInputType.emailAddress),
          const SizedBox(height: 12),

          _buildPasswordField(),
          const SizedBox(height: 12),

          if (!_isLoginMode) ...[
            _buildPhoneField(),
            const SizedBox(height: 12),
            _buildReferralField(),
            const SizedBox(height: 12),
          ],

          if (_isLoginMode) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _snack('Reset link sent to your email', _primary),
                style: TextButton.styleFrom(foregroundColor: _primary, padding: EdgeInsets.zero),
                child: const Text('Forgot password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 8),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : (_isLoginMode ? _login : _signup),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLoginMode ? _primary : _accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade200,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    _isLoginMode ? 'Sign in' : 'Create account',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 20),

          // Toggle
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              _isLoginMode ? "Don't have an account? " : "Already have an account? ",
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            GestureDetector(
              onTap: _toggleMode,
              child: Text(
                _isLoginMode ? 'Sign up' : 'Sign in',
                style: const TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Terms
          Center(child: RichText(textAlign: TextAlign.center, text: const TextSpan(
            text: 'By continuing, you agree to our ',
            style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            children: [
              TextSpan(text: 'Terms of Service',
                style: TextStyle(color: _primary, fontWeight: FontWeight.w600)),
              TextSpan(text: ' and '),
              TextSpan(text: 'Privacy Policy',
                style: TextStyle(color: _primary, fontWeight: FontWeight.w600)),
            ],
          ))),
        ]),
      ),
    );
  }

  // ── Field builders ────────────────────────────────────────────
  Widget _buildField(String label, String hint, TextEditingController ctrl,
    {TextInputType keyboard = TextInputType.text}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: Color(0xFF64748B), letterSpacing: 0.3)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0))),
        child: TextField(controller: ctrl, keyboardType: keyboard, enabled: !_loading,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
          decoration: InputDecoration(hintText: hint,
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
      ),
    ]);
  }

  Widget _buildPasswordField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: Color(0xFF64748B), letterSpacing: 0.3)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Expanded(child: TextField(controller: _passwordCtrl,
            obscureText: _obscurePassword, enabled: !_loading,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
            decoration: const InputDecoration(hintText: '••••••••',
              hintStyle: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),
          IconButton(
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: const Color(0xFF94A3B8), size: 20)),
        ]),
      ),
    ]);
  }

  Widget _buildPhoneField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Phone number (optional)', style: TextStyle(fontSize: 12,
        fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0)))),
            child: const Text('+91', style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
          Expanded(child: TextField(controller: _phoneCtrl,
            keyboardType: TextInputType.phone, enabled: !_loading, maxLength: 10,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
            decoration: const InputDecoration(counterText: '', hintText: '98765 43210',
              hintStyle: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14)))),
        ]),
      ),
    ]);
  }

  Widget _buildReferralField() {
    final borderColor = _referralError != null
      ? Colors.red.shade300
      : _referralValid ? Colors.green.shade300
      : const Color(0xFFE2E8F0);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Referral code (optional)', style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3)),
        if (_referralValid) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 12),
              const SizedBox(width: 3),
              Text('Valid', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: _referralError != null || _referralValid ? 1.5 : 1)),
        child: Row(children: [
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.card_giftcard_rounded, color: Color(0xFF94A3B8), size: 18),
          ),
          Expanded(child: TextField(
            controller: _referralCtrl, enabled: !_loading,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => setState(() { _referralError = null; _referralValid = false; }),
            onSubmitted: _validateReferral,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B), letterSpacing: 1),
            decoration: const InputDecoration(
              hintText: 'e.g. SUMMER2026',
              hintStyle: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.normal, letterSpacing: 0),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
          )),
          if (_referralCtrl.text.isNotEmpty)
            TextButton(
              onPressed: () => _validateReferral(_referralCtrl.text),
              style: TextButton.styleFrom(foregroundColor: _primary),
              child: const Text('Apply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      if (_referralError != null) ...[
        const SizedBox(height: 4),
        Row(children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 13),
          const SizedBox(width: 4),
          Text(_referralError!, style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
        ]),
      ],
    ]);
  }
}
