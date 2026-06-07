import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:message_me/screens/onboarding_screen.dart';
import 'package:message_me/screens/PermissionSetupScreen.dart';
import 'package:message_me/screens/splash_screen.dart';
import 'package:message_me/service/crash_reporter.dart';
import 'package:message_me/service/fcm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 1. Initialize crash reporter FIRST — catches all errors from here on
  CrashReporter.initialize();

  // ✅ 2. Initialize Firebase
  await Firebase.initializeApp();

  // ✅ 3. Register FCM background handler before any other firebase calls
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // ✅ 4. Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ✅ 5. Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // ✅ 6. Read prefs ONLY — no heavy init before UI shows
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  final permissionsDone = prefs.getBool('permissions_setup_done') ?? false;

  // ✅ 7. Show UI immediately — all heavy init happens inside SplashScreen
  runApp(MyApp(
    showOnboarding: !onboardingDone,
    showPermissions: onboardingDone && !permissionsDone,
  ));
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
      title: 'Smart Pinger',
      theme: ThemeData(
        primaryColor: const Color(0xFF5B67F1),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B67F1),
          primary: const Color(0xFF5B67F1),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF5B67F1),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        fontFamily: 'Roboto',
        useMaterial3: false,
      ),
      home: showOnboarding
          ? const OnboardingScreen()
          : showPermissions
              ? const PermissionSetupScreen()
              : const SplashScreen(),
    );
  }
}
