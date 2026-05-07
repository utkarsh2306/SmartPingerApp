import 'package:flutter/material.dart';
import 'package:message_me/screens/PermissionSetupScreen.dart';
import 'package:message_me/screens/onboarding_screen.dart';
import 'package:message_me/screens/splash_screen.dart';
import 'package:message_me/service/background_service.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/notification_service.dart';
import 'package:message_me/service/permission_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await PermissionService.request();
  } catch (_) {}

  try {
    await BackgroundServiceManager.initialize();
    await BackgroundServiceManager.start();
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();

  // ✅ Auto-enable if rules exist and user never explicitly disabled
  try {
    final db = await DatabaseService.db;
    final rules = await db.query('auto_sms_rules', where: 'is_active = 1');
    final explicitlyDisabled = prefs.getBool('user_disabled_trigger') ?? false;
    if (rules.isNotEmpty && !explicitlyDisabled) {
      await prefs.setBool('auto_trigger_enabled', true);
      debugPrint('✅ Auto-trigger enabled — ${rules.length} active rules found');
    }
  } catch (_) {}

  final wasEnabled = prefs.getBool('auto_trigger_enabled') ?? false;

  try {
    await BackgroundServiceManager.syncRulesToNative(enabled: wasEnabled);
  } catch (_) {}

  try {
    await NotificationService().initTable();
  } catch (_) {}

  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final permissionsDone = prefs.getBool('permissions_setup_done') ?? false;

  runApp(
    MyApp(
      showOnboarding: !onboardingDone,
      showPermissions: onboardingDone && !permissionsDone,
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool showOnboarding;
  final bool showPermissions;

  const MyApp({
    super.key,
    required this.showOnboarding,
    required this.showPermissions,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SMS Marketing',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey.shade100,
      ),
      home: showOnboarding
          ? const OnboardingScreen()
          : showPermissions
          ? const PermissionSetupScreen()
          : const SplashScreen(),
    );
  }
}
