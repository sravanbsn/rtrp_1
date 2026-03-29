import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/login_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/drishti_voice_bar.dart';
import '../../widgets/listening_mic_orb.dart';

class LoginPhoneScreen extends StatefulWidget {
  const LoginPhoneScreen({super.key});

  @override
  State<LoginPhoneScreen> createState() => _LoginPhoneScreenState();
}

class _LoginPhoneScreenState extends State<LoginPhoneScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _showTypeField = false;
  final TextEditingController _typeCtrl = TextEditingController();

  static const String _openLine = 'Wapas aa gaaye! Phone number boliye.';

  @override
  void initState() {
    super.initState();
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();
    context.read<LoginNotifier>().clearPhone();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await context.read<VoiceService>().speak(_openLine);
    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    _startListening(); // auto-listen — no tap needed
  }

  void _startListening() {
    if (!_speechAvailable || !mounted) return;
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (result.finalResult) {
          _handleSpokenPhone(result.recognizedWords);
        } else {
          // Live digit preview as user speaks
          final live = _extractDigits(result.recognizedWords);
          if (live.isNotEmpty) {
            context.read<LoginNotifier>().setPendingPhone(live);
          }
        }
      },
    );
  }

  Future<void> _handleSpokenPhone(String spoken) async {
    final lower = spoken.toLowerCase();
    // Wake-word for forgot flow
    if (lower.contains('yaad nahi') ||
        lower.contains('bhool') ||
        lower.contains('forgot')) {
      _goForgot();
      return;
    }

    final digits = _extractDigits(spoken);
    if (digits.length < 10) {
      await context.read<VoiceService>().speak(
            'Woh sahi nahi laga. Dobara boliye apna 10 digit number.',
          );
      Future.delayed(const Duration(milliseconds: 2200), _startListening);
      return;
    }

    context.read<LoginNotifier>().setPendingPhone(digits.substring(0, 10));
    await _sendOtp();
  }

  Future<void> _sendOtp() async {
    final login = context.read<LoginNotifier>();
    if (login.pendingPhone.length < 10) return;

    await context.read<VoiceService>().speak('OTP bhej rahi hoon.');
    await login.sendOtp();
    if (mounted) Navigator.pushReplacementNamed(context, '/login/otp');
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

  void _goForgot() {
    context
        .read<VoiceService>()
        .speak('Koi baat nahi. Guardian se madad lete hain.');
    Navigator.pushReplacementNamed(context, '/login/forgot');
  }

  @override
  void dispose() {
    _speech.stop();
    _typeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final login = context.watch<LoginNotifier>();
    final phone = login.pendingPhone;
    final isLoading = login.status == LoginStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── TOP 40% — navy + orb ────────────────────────────
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Radial glow behind orb
                      Container(
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              AppColors.saffronGlow,
                              Colors.transparent,
                            ],
                            radius: 0.75,
                          ),
                        ),
                      ),

                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ListeningMicOrb(
                            state: isLoading
                                ? ListeningOrbState.loading
                                : ListeningOrbState.listening,
                            onTap: isLoading ? null : _startListening,
                          )
                              .animate()
                              .fadeIn(duration: 600.ms)
                              .scale(begin: const Offset(0.85, 0.85)),
                          const SizedBox(height: AppSizes.md),
                          Text(
                            'Drishti sun rahi hai...',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.saffronLight,
                                  fontStyle: FontStyle.italic,
                                ),
                          )
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .fadeIn(
                                  duration: 1200.ms, curve: Curves.easeInOut),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── BOTTOM 60% — lighter panel ────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: AppColors.navyMid,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSizes.lg, AppSizes.xl, AppSizes.lg, AppSizes.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Welcome back heading
                          Text(
                            'Wapas Aa Gaaye! 👋',
                            style: Theme.of(context).textTheme.headlineLarge,
                          )
                              .animate()
                              .fadeIn(duration: 500.ms)
                              .slideY(begin: 0.2, end: 0),

                          const SizedBox(height: AppSizes.sm),

                          Text(
                            'Phone number boliye ya likhein',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.textMuted),
                          ).animate(delay: 150.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.xl),

                          // ── Masked phone display ────────────────────
                          _MaskedPhoneField(
                            digits: phone,
                            onTap: () {
                              setState(() => _showTypeField = !_showTypeField);
                            },
                          ).animate(delay: 250.ms).fadeIn(duration: 400.ms),

                          const SizedBox(height: AppSizes.lg),

                          // ── Type field toggle ────────────────────────
                          if (_showTypeField)
                            _TypePhoneField(
                              controller: _typeCtrl,
                              onSubmit: () {
                                final d = _extractDigits(_typeCtrl.text);
                                context
                                    .read<LoginNotifier>()
                                    .setPendingPhone(d);
                                _sendOtp();
                              },
                            )
                                .animate()
                                .fadeIn(duration: 300.ms)
                                .slideY(begin: -0.1, end: 0),

                          const SizedBox(height: AppSizes.lg),

                          // ── Send OTP button ───────────────────────────
                          Semantics(
                            label:
                                'Send OTP. Say your phone number to auto-send.',
                            child: ElevatedButton.icon(
                              onPressed: phone.length == 10 && !isLoading
                                  ? _sendOtp
                                  : null,
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.navyDeep,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded,
                                      color: AppColors.navyDeep),
                              label: Text(isLoading
                                  ? 'Bhej rahi hoon...'
                                  : 'OTP Bhejein'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: phone.length == 10
                                    ? AppColors.saffron
                                    : AppColors.navyCard,
                                foregroundColor: AppColors.navyDeep,
                                minimumSize: const Size(
                                    double.infinity, AppSizes.minTouchTarget),
                              ),
                            ),
                          ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

                          const Spacer(),

                          // ── Divider + Google + Forgot ─────────────────
                          _BottomActions(onForgot: _goForgot),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── Persistent voice bar ──────────────────────────────────
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Masked phone field — shows dots for entered digits
// ─────────────────────────────────────────────────────────────────────────────

class _MaskedPhoneField extends StatelessWidget {
  final String digits;
  final VoidCallback onTap;

  const _MaskedPhoneField({required this.digits, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Show +91 and masked dots
    final filled = digits.length;
    final masked = List.generate(10, (i) {
      if (i < filled) return i < 6 ? '●' : digits[i]; // first 6 masked
      return '○';
    });
    final display =
        '${masked.sublist(0, 5).join('')}  ${masked.sublist(5).join('')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppSizes.minTouchTarget + 8,
        decoration: BoxDecoration(
          color: AppColors.navyCard,
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          border: Border.all(
            color: filled > 0
                ? AppColors.saffron.withOpacity(0.5)
                : AppColors.navyLight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
        child: Row(
          children: [
            Text(
              '+91  ',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 18,
                  ),
            ),
            Expanded(
              child: Text(
                filled > 0 ? display : '○○○○○  ○○○○○',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: filled > 0
                          ? AppColors.saffronLight
                          : AppColors.textMuted,
                      fontSize: 20,
                      letterSpacing: 3,
                    ),
              ),
            ),
            if (filled == 10)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.safeGreen, size: 22),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type-in phone field
// ─────────────────────────────────────────────────────────────────────────────

class _TypePhoneField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _TypePhoneField({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            autofocus: true,
            style: const TextStyle(
                color: AppColors.white, fontSize: 18, letterSpacing: 2),
            decoration: InputDecoration(
              counterText: '',
              hintText: '10-digit number',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.navyCard,
              prefixText: '+91  ',
              prefixStyle: const TextStyle(
                  color: AppColors.textMuted, fontSize: 18, letterSpacing: 1),
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
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Semantics(
          label: 'Submit phone number',
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

// ─────────────────────────────────────────────────────────────────────────────
// Bottom actions — divider, Google, Forgot
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onForgot;
  const _BottomActions({required this.onForgot});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Divider with OR
        Row(children: [
          const Expanded(child: Divider(color: AppColors.navyLight)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: Text('ya',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textMuted)),
          ),
          const Expanded(child: Divider(color: AppColors.navyLight)),
        ]),

        const SizedBox(height: AppSizes.md),

        // TODO(dev): Implement google_sign_in package integration.
        // Button is disabled until the real OAuth flow is wired up.
        Semantics(
          label: 'Sign in with Google. Coming soon.',
          child: OutlinedButton.icon(
            onPressed: null, // disabled — not yet implemented
            icon: const Icon(Icons.g_mobiledata_rounded,
                color: AppColors.textMuted, size: 28),
            label: const Text('Google se Sign In',
                style: TextStyle(color: AppColors.textMuted)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, AppSizes.minTouchTarget),
              side: const BorderSide(color: AppColors.navyLight),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.buttonRadius)),
            ),
          ),
        ),

        const SizedBox(height: AppSizes.md),

        // Forgot number
        Semantics(
          label: 'Forgot number. Say "Mujhe yaad nahi" to activate.',
          child: TextButton(
            onPressed: onForgot,
            child: Text(
              'Number yaad nahi? Guardian se madad lo',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textMuted,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        const SizedBox(height: 72), // voice bar clearance
      ],
    );
  }
}
