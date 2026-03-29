import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/setup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/setup_scaffold.dart';

class SetupLanguageScreen extends StatefulWidget {
  const SetupLanguageScreen({super.key});

  @override
  State<SetupLanguageScreen> createState() => _SetupLanguageScreenState();
}

class _SetupLanguageScreenState extends State<SetupLanguageScreen> {
  AppLanguage? _previewing;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        context
            .read<VoiceService>()
            .speak('Main kaun si bhasha mein baat karoon?');
      }
    });
  }

  Future<void> _selectLanguage(AppLanguage lang) async {
    final voice = context.read<VoiceService>();
    context.read<SetupNotifier>().setLanguage(lang);
    setState(() => _previewing = lang);

    // Immediately speak sample line in chosen language
    await voice.speak(lang.sampleLine);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      await voice.speak(
          lang == AppLanguage.hindi
              ? 'Haan bol den ya button dabayen.'
              : 'Say "Haan" or tap confirm.');
    }
  }

  Future<void> _confirm() async {
    final lang = context.read<SetupNotifier>().selectedLanguage;
    setState(() => _confirmed = true);
    await context.read<VoiceService>().speak(
          lang == AppLanguage.hindi
              ? 'Bahut acha! ${lang.displayName} set ho gaya.'
              : '${lang.displayName} language set!',
        );
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) Navigator.pushReplacementNamed(context, '/setup/haptic');
  }

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SetupNotifier>();
    final selected = setup.selectedLanguage;

    return SetupScaffold(
      step: SetupStep.language,
      title: 'Bhasha Chunein',
      subtitle: 'Drishti isi bhasha mein baat karegi.',
      icon: _LangIcon(confirmed: _confirmed),
      body: Column(
        children: [
          // 2×2 grid of language cards
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: AppSizes.md,
            mainAxisSpacing: AppSizes.md,
            childAspectRatio: 1.4,
            children: AppLanguage.values.map((lang) {
              final isSelected = selected == lang;
              return _LanguageCard(
                language: lang,
                isSelected: isSelected,
                isPreviewing: _previewing == lang,
                onTap: () => _selectLanguage(lang),
              );
            }).toList(),
          ),

          const SizedBox(height: AppSizes.xl),

          // Show confirm button after a language is previewed
          if (_previewing != null)
            Semantics(
              label: 'Confirm selected language',
              child: ElevatedButton(
                onPressed: _confirmed ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  minimumSize:
                      const Size(double.infinity, AppSizes.minTouchTarget),
                  backgroundColor:
                      _confirmed ? AppColors.safeGreen : AppColors.saffron,
                ),
                child: Text(_confirmed
                    ? '${selected.displayName} Set Ho Gaya ✓'
                    : 'Haan, Yahi Bhasha'),
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),
            ),
        ],
      ),
    );
  }
}

class _LangIcon extends StatelessWidget {
  final bool confirmed;
  const _LangIcon({this.confirmed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.saffronLight.withValues(alpha: 0.25),
            AppColors.saffron.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(
            color: AppColors.saffron.withValues(alpha: 0.5), width: 2),
      ),
      child: Center(
        child: Text(
          confirmed ? '✓' : '🗣️',
          style: const TextStyle(fontSize: 48),
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(end: 1.07, duration: 2000.ms, curve: Curves.easeInOut);
  }
}

class _LanguageCard extends StatelessWidget {
  final AppLanguage language;
  final bool isSelected;
  final bool isPreviewing;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.language,
    required this.isSelected,
    required this.isPreviewing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Select ${language.displayName} language',
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.saffron.withValues(alpha: 0.15)
                : AppColors.navyCard,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(
              color: isSelected
                  ? AppColors.saffron
                  : AppColors.navyLight,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.saffron.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(language.flag, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 6),
              Text(
                language.displayName,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: isSelected
                          ? AppColors.saffronLight
                          : AppColors.white,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 15,
                    ),
                textAlign: TextAlign.center,
              ),
              if (isPreviewing) ...[
                const SizedBox(height: 4),
                Container(
                  width: 24,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.saffron,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleX(end: 0.4, duration: 700.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
