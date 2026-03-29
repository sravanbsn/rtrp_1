import 'package:flutter/foundation.dart';

/// Tracks sign-up data collected across all 4 steps.
class SignUpNotifier extends ChangeNotifier {
  // ── Collected data ───────────────────────────────────────────────
  String name = '';
  String phoneNumber = '';
  UserType? userType;
  String otp = '';

  // ── Step state ───────────────────────────────────────────────────
  SignUpStep currentStep = SignUpStep.name;

  // ── Per-step status ──────────────────────────────────────────────
  StepStatus nameStatus = StepStatus.listening;
  StepStatus phoneStatus = StepStatus.listening;
  StepStatus userTypeStatus = StepStatus.listening;
  StepStatus otpStatus = StepStatus.listening;

  // ── Pending confirmation (Step 1 & 2) ───────────────────────────
  String pendingName = '';
  String pendingPhone = '';

  // ─────────────────────────────────────────────────────────────────
  // Step 1 — Name
  // ─────────────────────────────────────────────────────────────────

  void setPendingName(String value) {
    pendingName = value.trim();
    nameStatus = StepStatus.confirming;
    notifyListeners();
  }

  void confirmName() {
    name = pendingName;
    nameStatus = StepStatus.done;
    notifyListeners();
  }

  void rejectName() {
    pendingName = '';
    nameStatus = StepStatus.listening;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────
  // Step 2 — Phone
  // ─────────────────────────────────────────────────────────────────

  void setPendingPhone(String digits) {
    pendingPhone = digits.replaceAll(RegExp(r'\D'), '');
    phoneStatus = StepStatus.confirming;
    notifyListeners();
  }

  void confirmPhone() {
    phoneNumber = pendingPhone;
    phoneStatus = StepStatus.done;
    notifyListeners();
  }

  void rejectPhone() {
    pendingPhone = '';
    phoneStatus = StepStatus.listening;
    notifyListeners();
  }

  /// Append a digit during live dictation
  void appendPhoneDigit(String digit) {
    if (pendingPhone.length < 10) {
      pendingPhone += digit;
      notifyListeners();
    }
  }

  void clearPhone() {
    pendingPhone = '';
    phoneStatus = StepStatus.listening;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────
  // Step 3 — User Type
  // ─────────────────────────────────────────────────────────────────

  void selectUserType(UserType type) {
    userType = type;
    userTypeStatus = StepStatus.done;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────
  // Step 4 — OTP
  // ─────────────────────────────────────────────────────────────────

  void setOtp(String value) {
    otp = value.replaceAll(RegExp(r'\D'), '').substring(
        0, value.length.clamp(0, 6));
    notifyListeners();
  }

  void appendOtpDigit(String digit) {
    if (otp.length < 6) {
      otp += digit;
      notifyListeners();
    }
  }

  void setOtpStatus(StepStatus status) {
    otpStatus = status;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────

  void goToStep(SignUpStep step) {
    currentStep = step;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────
  // Reset
  // ─────────────────────────────────────────────────────────────────

  void reset() {
    name = '';
    phoneNumber = '';
    userType = null;
    otp = '';
    pendingName = '';
    pendingPhone = '';
    currentStep = SignUpStep.name;
    nameStatus = StepStatus.listening;
    phoneStatus = StepStatus.listening;
    userTypeStatus = StepStatus.listening;
    otpStatus = StepStatus.listening;
    notifyListeners();
  }
}

enum SignUpStep { name, phone, userType, otp }

enum StepStatus { listening, confirming, loading, done, error }

enum UserType { user, guardian }
