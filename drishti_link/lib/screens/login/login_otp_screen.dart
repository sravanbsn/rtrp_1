import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/login_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/drishti_voice_bar.dart';
import '../../widgets/listening_mic_orb.dart';

class LoginOtpScreen extends StatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _showTypeField = false;
  final TextEditingController _otpCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();
    if (!mounted) return;
    context.read<LoginNotifier>().clearOtp();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await context.read<VoiceService>().speak('Code aaya? Boliye.');
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    _startListening();
  }

  void _startListening() {
    if (!_speechAvailable || !mounted) return;
    final login = context.read<LoginNotifier>();
    if (login.status == LoginStatus.loading ||
        login.status == LoginStatus.success) {
      return;
    }

    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 2),
      onResult: (result) {
        if (result.finalResult) {
          _handleSpokenOtp(result.recognizedWords);
        } else {
          // Live preview
          final digits = _extractDigits(result.recognizedWords);
          if (digits.isNotEmpty) {
            context.read<LoginNotifier>().setOtp(digits);
          }
        }
      },
    );
  }

  Future<void> _handleSpokenOtp(String spoken) async {
    final digits = _extractDigits(spoken);
    final login = context.read<LoginNotifier>();

    if (digits.isEmpty) {
      await context.read<VoiceService>().speak(
            'Woh sahi nahi laga. Dobara boliye?',
          );
      Future.delayed(const Duration(milliseconds: 2000), _startListening);
      return;
    }

    login.setOtp(digits);

    if (login.otp.length == 6) {
      await _verify();
    } else {
      await context.read<VoiceService>().speak(
            '${login.otp.length} digits mile. Poora 6 digit OTP boliye.',
          );
      Future.delayed(const Duration(milliseconds: 2200), _startListening);
    }
  }

  String _extractDigits(String spoken) {
    const wordMap = {
      'zero': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'shunya': '0',
      'ek': '1',
      'do': '2',
      'teen': '3',
      'chaar': '4',
      'paanch': '5',
      'chheh': '6',
      'saat': '7',
      'aath': '8',
      'nau': '9',
    };
    var s = spoken.toLowerCase();
    wordMap.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _verify() async {
    _speech.stop();
    final login = context.read<LoginNotifier>();
    final voice = context.read<VoiceService>();

    final success = await login.verifyOtp();

    if (!mounted) return;

    if (success) {
      await voice.speak('Perfect. Andar chalte hain.');
      await Future.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;

      // Route to biometric for returning users, home for new users
      if (login.isReturningUser) {
        Navigator.pushReplacementNamed(context, '/login/biometric');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      // Voice the specific error
      final msg = login.errorMessage(login.error);
      if (msg.isNotEmpty) await voice.speak(msg);

      if (login.error == LoginError.expiredOtp) {
        await login.resendOtp();
      }
      await Future.delayed(const Duration(milliseconds: 2500));
      if (mounted) _startListening();
    }
  }

  void _submitTypedOtp() {
    final digits = _otpCtrl.text.replaceAll(RegExp(r'\D'), '');
    final login = context.read<LoginNotifier>();
    login.setOtp(digits);
    if (login.otp.length == 6) {
      setState(() => _showTypeField = false);
      _verify();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final login = context.watch<LoginNotifier>();
    final status = login.status;
    final otp = login.otp;
    final hasError = status == LoginStatus.error;
    final isLoading = status == LoginStatus.loading;
    final isSuccess = status == LoginStatus.success;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── TOP 40% — orb ───────────────────────────────────
                SizedBox(
                  height: size.height * 0.40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              (hasError
                                      ? AppColors.hazardRed
                                      : isSuccess
                                          ? AppColors.safeGreen
                                          : AppColors.saffron)
                                  .withOpacity(0.12),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      ListeningMicOrb(
                        state: isLoading
                            ? ListeningOrbState.loading
                            : isSuccess
                                ? ListeningOrbState.done
                                : ListeningOrbState.listening,
                        onTap: isLoading || isSuccess ? null : _startListening,
                      ).animate().fadeIn(duration: 500.ms),
                    ],
                  ),
                ),

                // ── BOTTOM 60% — panel ───────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: AppColors.navyMid,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                          AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OTP Darj Karein',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ).animate().fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.sm),

                          Text(
                            '+91 ${_formatPhone(login.phone)} pe code bheja',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.xl),

                          // OTP boxes
                          _OtpBoxRow(
                            otp: otp,
                            hasError: hasError,
                            isSuccess: isSuccess,
                          ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.lg),

                          // Error banner
                          AnimatedSwitcher(
                            duration: AppDurations.medium,
                            child: hasError
                                ? _ErrorBanner(
                                        message:
                                            login.errorMessage(login.error))
                                    .animate()
                                    .fadeIn(duration: 300.ms)
                                    .shake(hz: 4, offset: const Offset(4, 0))
                                : const SizedBox.shrink(),
                          ),

                          const SizedBox(height: AppSizes.lg),

                          // ── Keyboard type-in fallback ────────────────
                          if (_showTypeField)
                            _TypeOtpField(
                              controller: _otpCtrl,
                              onSubmit: _submitTypedOtp,
                            )
                                .animate()
                                .fadeIn(duration: 300.ms)
                                .slideY(begin: -0.1, end: 0),

                          const SizedBox(height: AppSizes.md),

                          // Toggle type field
                          Center(
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _showTypeField = !_showTypeField;
                                  if (!_showTypeField) _otpCtrl.clear();
                                });
                              },
                              child: Text(
                                _showTypeField
                                    ? 'Voice se bolein'
                                    : 'OTP manually type karein',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppColors.textMuted,
                                      decoration: TextDecoration.underline,
                                      decorationColor: AppColors.textMuted,
                                    ),
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSizes.lg),

                          // Verify button
                          ElevatedButton(
                            onPressed:
                                otp.length == 6 && !isLoading && !isSuccess
                                    ? _verify
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSuccess
                                  ? AppColors.safeGreen
                                  : AppColors.saffron,
                              minimumSize: const Size(
                                  double.infinity, AppSizes.minTouchTarget),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.navyDeep),
                                  )
                                : Text(isSuccess
                                    ? 'Verified! ✓'
                                    : 'Verify Karein'),
                          ).animate(delay: 350.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.md),

                          // Resend row
                          _ResendRow(
                            countdown: login.resendCountdown,
                            onResend: () async {
                              await context.read<VoiceService>().speak(
                                    'Naya OTP bhej rahi hoon.',
                                  );
                              await login.resendOtp();
                            },
                          ),

                          const SizedBox(height: 80), // voice bar clearance
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DrishtiVoiceBar(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPhone(String p) =>
      p.length == 10 ? '${p.substring(0, 5)} ${p.substring(5)}' : p;
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TypeOtpField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _TypeOtpField({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
                color: AppColors.white, fontSize: 22, letterSpacing: 6),
            decoration: InputDecoration(
              counterText: '',
              hintText: '______',
              hintStyle: const TextStyle(
                  color: AppColors.textMuted, fontSize: 22, letterSpacing: 6),
              filled: true,
              fillColor: AppColors.navyCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                borderSide:
                    const BorderSide(color: AppColors.saffron, width: 2),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            onChanged: (val) {
              // auto-submit when 6 digits typed
              if (val.length == 6) onSubmit();
            },
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Semantics(
          label: 'Submit OTP',
          child: IconButton(
            onPressed: onSubmit,
            icon: const Icon(Icons.arrow_forward_rounded,
                color: AppColors.saffron),
            iconSize: 32,
          ),
        ),
      ],
    );
  }
}

class _OtpBoxRow extends StatelessWidget {
  final String otp;
  final bool hasError;
  final bool isSuccess;
  const _OtpBoxRow(
      {required this.otp, required this.hasError, required this.isSuccess});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) {
        final hasDigit = i < otp.length;
        final isNext = i == otp.length;
        final digit = hasDigit ? otp[i] : '';

        Color borderColor = hasDigit
            ? (hasError
                ? AppColors.hazardRed
                : isSuccess
                    ? AppColors.safeGreen
                    : AppColors.saffron.withOpacity(0.7))
            : isNext
                ? AppColors.saffron
                : AppColors.navyLight;

        return AnimatedContainer(
          duration: AppDurations.fast,
          width: 46,
          height: 60,
          decoration: BoxDecoration(
            color: hasDigit
                ? (hasError
                    ? AppColors.hazardRed.withOpacity(0.1)
                    : AppColors.saffron.withOpacity(0.1))
                : AppColors.navyCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: isNext ? 2.5 : 1.5),
          ),
          child: Center(
            child: Text(
              digit,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color:
                        hasError ? AppColors.hazardRed : AppColors.saffronLight,
                    fontSize: 26,
                  ),
            ),
          ),
        );
      }),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.hazardRed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: AppColors.hazardRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.hazardRed, size: 20),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.hazardRed,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  final int countdown;
  final VoidCallback onResend;
  const _ResendRow({required this.countdown, required this.onResend});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Code nahi aya? ',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
        countdown > 0
            ? Text(
                '$countdown sec mein bhejen',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textMuted),
              )
            : TextButton(
                onPressed: onResend,
                child: const Text('Dobara bhejein',
                    style: TextStyle(color: AppColors.saffron)),
              ),
      ],
    );
  }
}
