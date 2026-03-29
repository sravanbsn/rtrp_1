import 'package:flutter/foundation.dart';

/// Which setup step the user is currently on (1-indexed to match progress bar).
enum SetupStep { camera, location, guardian, language, haptic }

/// Language choices available in the setup flow.
enum AppLanguage { hindi, english, telugu, tamil }

extension AppLanguageLabel on AppLanguage {
  String get displayName {
    switch (this) {
      case AppLanguage.hindi:
        return 'हिंदी';
      case AppLanguage.english:
        return 'English';
      case AppLanguage.telugu:
        return 'తెలుగు';
      case AppLanguage.tamil:
        return 'தமிழ்';
    }
  }

  String get sampleLine {
    switch (this) {
      case AppLanguage.hindi:
        return 'Namaste! Main Drishti hoon, aapki aankhen.';
      case AppLanguage.english:
        return 'Hello! I am Drishti, your eyes.';
      case AppLanguage.telugu:
        return 'Namaskaram! Nenu Drishti, meeru kannu.';
      case AppLanguage.tamil:
        return 'Vanakkam! Naan Drishti, ungal kann.';
    }
  }

  String get flag => '🇮🇳';
}

/// Haptic intensity the user selected.
enum HapticIntensity { low, medium, high }

/// Manages state for the 5-screen first-time setup wizard.
class SetupNotifier extends ChangeNotifier {
  SetupStep currentStep = SetupStep.camera;

  // ── Permissions ───────────────────────────────────────────────────
  bool cameraGranted = false;
  bool locationGranted = false;

  // ── Guardian ──────────────────────────────────────────────────────
  /// Simulated contact that was selected as guardian.
  Map<String, String>? selectedGuardian; // {name, phone, initials}

  // ── Language ──────────────────────────────────────────────────────
  AppLanguage selectedLanguage = AppLanguage.hindi;

  // ── Haptic ────────────────────────────────────────────────────────
  HapticIntensity hapticIntensity = HapticIntensity.medium;
  bool hapticConfirmed = false;

  // ── Step progress ─────────────────────────────────────────────────
  int get stepIndex => SetupStep.values.indexOf(currentStep);
  int get totalSteps => SetupStep.values.length;

  void goToStep(SetupStep step) {
    currentStep = step;
    notifyListeners();
  }

  void advanceStep() {
    final idx = stepIndex;
    if (idx < totalSteps - 1) {
      currentStep = SetupStep.values[idx + 1];
      notifyListeners();
    }
  }

  // ── Per-step setters ──────────────────────────────────────────────

  void setCameraGranted(bool v) {
    cameraGranted = v;
    notifyListeners();
  }

  void setLocationGranted(bool v) {
    locationGranted = v;
    notifyListeners();
  }

  void setGuardian(Map<String, String> contact) {
    selectedGuardian = contact;
    notifyListeners();
  }

  void setLanguage(AppLanguage lang) {
    selectedLanguage = lang;
    notifyListeners();
  }

  void setHapticIntensity(HapticIntensity intensity) {
    hapticIntensity = intensity;
    notifyListeners();
  }

  void confirmHaptic() {
    hapticConfirmed = true;
    notifyListeners();
  }

  void reset() {
    currentStep = SetupStep.camera;
    cameraGranted = false;
    locationGranted = false;
    selectedGuardian = null;
    selectedLanguage = AppLanguage.hindi;
    hapticIntensity = HapticIntensity.medium;
    hapticConfirmed = false;
    notifyListeners();
  }
}
