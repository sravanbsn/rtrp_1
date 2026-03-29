import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/theme.dart';
import '../main.dart';
import '../services/voice_service.dart';
import '../widgets/drishti_voice_bar.dart';
import '../widgets/onboarding_slide.dart';
import '../widgets/illustrations/street_walker_illustration.dart';
import '../widgets/illustrations/camera_scan_illustration.dart';
import '../widgets/illustrations/guardian_map_illustration.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  static const List<_SlideData> _slides = [
    _SlideData(
      headline: 'Walk Without Fear',
      subtext: 'AI watches the road so you don\'t have to',
      drishtiLine: 'Drishti-Link ke saath, aap akele nahi hain.',
    ),
    _SlideData(
      headline: 'See Before You Step',
      subtext: 'Your phone\'s camera becomes your eyes',
      drishtiLine: 'Aapka phone ab aapki aankhein hai.',
    ),
    _SlideData(
      headline: 'Never Alone',
      subtext: 'Your guardian is always watching over you',
      drishtiLine: 'Aapka guardian har waqt saath hai.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrentSlide(0));
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _startListening();
        }
      },
    );
    if (_speechAvailable) _startListening();
  }

  void _startListening() {
    if (!_speechAvailable || !mounted) return;
    _speech.listen(
      localeId: 'hi_IN',
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        final page = context.read<OnboardingNotifier>().pageIndex;

        if (words.contains('agla') || words.contains('next')) {
          _goNext(page);
        } else if (words.contains('pichla') || words.contains('back')) {
          _goPrev(page);
        } else if (words.contains('shuru') ||
            words.contains('start') ||
            words.contains('started')) {
          _finish();
        } else if (words.contains('skip') || words.contains('skip')) {
          _skip();
        }
      },
    );
  }

  void _speakCurrentSlide(int index) {
    if (!mounted) return;
    context.read<VoiceService>().speak(_slides[index].drishtiLine);
    context.read<OnboardingNotifier>().setPage(index);
  }

  void _goNext(int current) {
    if (current < _slides.length - 1) {
      _pageController.nextPage(
        duration: AppDurations.medium,
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _goPrev(int current) {
    if (current > 0) {
      _pageController.previousPage(
        duration: AppDurations.medium,
        curve: Curves.easeInOut,
      );
    }
  }

  void _skip() {
    context.read<VoiceService>().speak('Theek hai, seedha chalte hain.');
    Navigator.pushReplacementNamed(context, '/signup/name');
  }

  void _finish() {
    context
        .read<VoiceService>()
        .speak('Chaliye shuru karte hain. Pehle account banate hain.');
    Navigator.pushReplacementNamed(context, '/signup/name');
  }

  @override
  void dispose() {
    _speech.stop();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = context.watch<OnboardingNotifier>().pageIndex;
    final isLastPage = currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.navyDeep,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Page view ───────────────────────────────────────────
            PageView(
              controller: _pageController,
              onPageChanged: _speakCurrentSlide,
              children: [
                OnboardingSlide(
                  illustration: const StreetWalkerIllustration(),
                  headline: _slides[0].headline,
                  subtext: _slides[0].subtext,
                ),
                OnboardingSlide(
                  illustration: const CameraScanIllustration(),
                  headline: _slides[1].headline,
                  subtext: _slides[1].subtext,
                ),
                OnboardingSlide(
                  illustration: const GuardianMapIllustration(),
                  headline: _slides[2].headline,
                  subtext: _slides[2].subtext,
                ),
              ],
            ),

            // ── Skip button (top right) ──────────────────────────────
            if (!isLastPage)
              Positioned(
                top: 12,
                right: 16,
                child: Semantics(
                  label: 'Skip onboarding. Say "Skip" to activate.',
                  child: TextButton(
                    onPressed: _skip,
                    child: const Text('Skip'),
                  ),
                ),
              ),

            // ── Bottom controls ──────────────────────────────────────
            Positioned(
              bottom: 72, // above voice bar
              left: 0,
              right: 0,
              child: _BottomControls(
                pageController: _pageController,
                currentPage: currentPage,
                totalPages: _slides.length,
                isLastPage: isLastPage,
                onNext: () => _goNext(currentPage),
                onFinish: _finish,
              ),
            ),

            // ── Persistent voice bar ─────────────────────────────────
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

class _BottomControls extends StatelessWidget {
  final PageController pageController;
  final int currentPage;
  final int totalPages;
  final bool isLastPage;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  const _BottomControls({
    required this.pageController,
    required this.currentPage,
    required this.totalPages,
    required this.isLastPage,
    required this.onNext,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dot indicator
          SmoothPageIndicator(
            controller: pageController,
            count: totalPages,
            effect: const ExpandingDotsEffect(
              activeDotColor: AppColors.saffron,
              dotColor: AppColors.navyCard,
              dotHeight: 8,
              dotWidth: 8,
              expansionFactor: 4,
            ),
          ),

          const SizedBox(height: AppSizes.lg),

          // CTA button
          AnimatedSwitcher(
            duration: AppDurations.medium,
            child: isLastPage
                ? Semantics(
                    label: 'Get Started. Say "Shuru karo" to activate.',
                    child: ElevatedButton(
                      key: const ValueKey('get_started'),
                      onPressed: onFinish,
                      child: const Text('Get Started'),
                    ),
                  )
                : Semantics(
                    label: 'Next slide. Say "Agla" to activate.',
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _NextButton(onTap: onNext),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NextButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.saffron,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.saffronGlow,
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_forward_rounded,
          color: AppColors.navyDeep,
          size: 28,
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(end: 1.05, duration: 900.ms, curve: Curves.easeInOut);
  }
}

class _SlideData {
  final String headline;
  final String subtext;
  final String drishtiLine;
  const _SlideData({
    required this.headline,
    required this.subtext,
    required this.drishtiLine,
  });
}
