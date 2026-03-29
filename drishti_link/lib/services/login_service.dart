import 'dart:async';
import 'package:flutter/foundation.dart';

/// State machine for the login flow.
enum LoginStep { phone, otp, biometric, forgot }
enum LoginStatus { idle, listening, loading, success, error }
enum LoginError { none, wrongOtp, expiredOtp, noNetwork, unknown }

class LoginNotifier extends ChangeNotifier {
  // ── Data ─────────────────────────────────────────────────────────
  String phone = '';
  String otp = '';
  bool isReturningUser = false; // true → route to biometric after OTP success

  // ── Status ───────────────────────────────────────────────────────
  LoginStep step = LoginStep.phone;
  LoginStatus status = LoginStatus.idle;
  LoginError error = LoginError.none;

  // Pending (privacy: masked on screen until confirmed)
  String _pendingPhone = '';
  String get pendingPhone => _pendingPhone;

  // OTP resend timer — stored so it can be cancelled
  int resendCountdown = 0;
  Timer? _resendTimer;

  // ── Phone ─────────────────────────────────────────────────────────

  void setPendingPhone(String digits) {
    _pendingPhone = digits.replaceAll(RegExp(r'\D'), '');
    status = LoginStatus.idle;
    error = LoginError.none;
    notifyListeners();
  }

  void clearPhone() {
    _pendingPhone = '';
    notifyListeners();
  }

  Future<void> sendOtp() async {
    if (_pendingPhone.length < 10) return;
    phone = _pendingPhone;
    status = LoginStatus.loading;
    error = LoginError.none;
    notifyListeners();

    // TODO: replace with real OTP API call
    await Future.delayed(const Duration(seconds: 1));
    step = LoginStep.otp;
    status = LoginStatus.idle;
    resendCountdown = 30;
    notifyListeners();
    _startResendTimer();
  }

  // ── Resend timer (cancellable) ────────────────────────────────────

  void _startResendTimer() {
    _resendTimer?.cancel();
    resendCountdown = 30;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (resendCountdown <= 0) {
        t.cancel();
        _resendTimer = null;
        return;
      }
      resendCountdown--;
      notifyListeners();
    });
  }

  // ── OTP ──────────────────────────────────────────────────────────

  void appendOtpDigit(String digit) {
    if (otp.length < 6) {
      otp += digit;
      notifyListeners();
    }
  }

  void setOtp(String value) {
    otp = value.replaceAll(RegExp(r'\D'), '');
    if (otp.length > 6) otp = otp.substring(0, 6);
    notifyListeners();
  }

  void clearOtp() {
    otp = '';
    error = LoginError.none;
    status = LoginStatus.idle;
    notifyListeners();
  }

  Future<bool> verifyOtp() async {
    status = LoginStatus.loading;
    error = LoginError.none;
    notifyListeners();

    // TODO: replace with real OTP verification API
    await Future.delayed(const Duration(seconds: 2));

    // Simulate: "123456" is always correct for demo
    if (otp == '123456') {
      status = LoginStatus.success;
      notifyListeners();
      return true;
    }

    // Simulate error states
    if (otp == '000000') {
      error = LoginError.expiredOtp;
    } else {
      error = LoginError.wrongOtp;
    }
    status = LoginStatus.error;
    otp = '';
    notifyListeners();
    return false;
  }

  Future<void> resendOtp() async {
    if (resendCountdown > 0) return;
    clearOtp();
    status = LoginStatus.loading;
    notifyListeners();
    // TODO: real resend API call
    await Future.delayed(const Duration(seconds: 1));
    status = LoginStatus.idle;
    notifyListeners();
    _startResendTimer();
  }

  // ── Biometric ────────────────────────────────────────────────────

  void goToBiometric() {
    isReturningUser = true;
    step = LoginStep.biometric;
    notifyListeners();
  }

  void setReturningUser(bool value) {
    isReturningUser = value;
    notifyListeners();
  }

  // ── Forgot ───────────────────────────────────────────────────────

  void goToForgot() {
    step = LoginStep.forgot;
    status = LoginStatus.idle;
    notifyListeners();
  }

  // ── Reset ─────────────────────────────────────────────────────────

  void reset() {
    _resendTimer?.cancel();
    _resendTimer = null;
    phone = '';
    otp = '';
    _pendingPhone = '';
    isReturningUser = false;
    step = LoginStep.phone;
    status = LoginStatus.idle;
    error = LoginError.none;
    resendCountdown = 0;
    notifyListeners();
  }

  String errorMessage(LoginError e) {
    switch (e) {
      case LoginError.wrongOtp:
        return 'Woh code sahi nahi tha. Dobara bhejoon?';
      case LoginError.expiredOtp:
        return 'Code purana ho gaya. Naya bhejti hoon.';
      case LoginError.noNetwork:
        return 'Internet nahi lag raha. Check karein.';
      case LoginError.unknown:
        return 'Kuch gadbad hui. Dobara koshish karein.';
      case LoginError.none:
        return ''; // no error — no message
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }
}
