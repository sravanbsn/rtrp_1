import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/voice_service.dart';
import 'services/signup_service.dart';
import 'services/login_service.dart';
import 'services/setup_service.dart';
import 'utils/connectivity_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/signup/step_name.dart';
import 'screens/signup/step_phone.dart';
import 'screens/signup/step_user_type.dart';
import 'screens/signup/step_otp.dart';
import 'screens/login/login_phone_screen.dart';
import 'screens/login/login_otp_screen.dart';
import 'screens/login/login_biometric_screen.dart';
import 'screens/login/login_forgot_screen.dart';
import 'screens/setup/setup_camera_screen.dart';
import 'screens/setup/setup_location_screen.dart';
import 'screens/setup/setup_guardian_screen.dart';
import 'screens/setup/setup_language_screen.dart';
import 'screens/setup/setup_haptic_screen.dart';
import 'screens/navigation_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/sos_setup_screen.dart';
import 'screens/routes_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/voice_settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for consistent accessibility experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Immersive — keep status bar light for accessibility indicators
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VoiceService()),
        ChangeNotifierProvider(create: (_) => OnboardingNotifier()),
        // Sign-up state persists across all 4 steps
        ChangeNotifierProvider(create: (_) => SignUpNotifier()),
        // Login state persists across phone → OTP → biometric
        ChangeNotifierProvider(create: (_) => LoginNotifier()),
        // First-time setup wizard (5 screens)
        ChangeNotifierProvider(create: (_) => SetupNotifier()),
        // Global connectivity monitoring
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: const DrishtiLinkApp(),
    ),
  );
}

class DrishtiLinkApp extends StatelessWidget {
  const DrishtiLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drishti-Link',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      initialRoute: '/',
      routes: {
        // ── Core flow ─────────────────────────────────────────────
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),

        // ── Sign-up flow (4 steps) ────────────────────────────────
        '/signup/name': (context) => const StepNameScreen(),
        '/signup/phone': (context) => const StepPhoneScreen(),
        '/signup/usertype': (context) => const StepUserTypeScreen(),
        '/signup/otp': (context) => const StepOtpScreen(),

        // ── Login flow ────────────────────────────────────────────
        '/login/phone': (context) => const LoginPhoneScreen(),
        '/login/otp': (context) => const LoginOtpScreen(),
        '/login/biometric': (context) => const LoginBiometricScreen(),
        '/login/forgot': (context) => const LoginForgotScreen(),

        // ── Active navigation ────────────────────────────────
        '/navigation': (context) => const NavigationScreen(),

        // ── Alerts + SOS ─────────────────────────────────────
        '/alerts': (context) => const AlertsScreen(),
        '/sos': (context) => const SosScreen(),
        '/sos/setup': (context) => const SosSetupScreen(),

        // ── Routes + Profile + Voice Settings ──────────────────────
        '/routes': (context) => const RoutesScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/voice-settings': (context) => const VoiceSettingsScreen(),
        '/setup/camera': (context) => const SetupCameraScreen(),
        '/setup/location': (context) => const SetupLocationScreen(),
        '/setup/guardian': (context) => const SetupGuardianScreen(),
        '/setup/language': (context) => const SetupLanguageScreen(),
        '/setup/haptic': (context) => const SetupHapticScreen(),
      },
    );
  }
}

/// Tracks the current onboarding page index globally.
class OnboardingNotifier extends ChangeNotifier {
  int _pageIndex = 0;

  int get pageIndex => _pageIndex;

  void setPage(int index) {
    _pageIndex = index;
    notifyListeners();
  }
}
