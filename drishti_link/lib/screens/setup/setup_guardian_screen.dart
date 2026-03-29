import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/setup_service.dart';
import '../../services/voice_service.dart';
import '../../widgets/setup_scaffold.dart';

/// Simulated contacts for demo — replace with flutter_contacts on native.
const List<Map<String, String>> _mockContacts = [
  {'name': 'Priya Sharma', 'phone': '+91 98765 43210', 'initials': 'PS'},
  {'name': 'Rahul Verma', 'phone': '+91 87654 32109', 'initials': 'RV'},
  {'name': 'Sunita Gupta', 'phone': '+91 76543 21098', 'initials': 'SG'},
  {'name': 'Amit Kumar', 'phone': '+91 65432 10987', 'initials': 'AK'},
  {'name': 'Neha Joshi', 'phone': '+91 54321 09876', 'initials': 'NJ'},
  {'name': 'Vijay Singh', 'phone': '+91 43210 98765', 'initials': 'VS'},
  {'name': 'Kavita Patel', 'phone': '+91 32109 87654', 'initials': 'KP'},
  {'name': 'Deepak Mehta', 'phone': '+91 21098 76543', 'initials': 'DM'},
];

class SetupGuardianScreen extends StatefulWidget {
  const SetupGuardianScreen({super.key});

  @override
  State<SetupGuardianScreen> createState() => _SetupGuardianScreenState();
}

class _SetupGuardianScreenState extends State<SetupGuardianScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  String _query = '';
  Map<String, String>? _pendingContact; // contact to confirm
  bool _confirmed = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text);
    });
    _initAndSpeak();
  }

  Future<void> _initAndSpeak() async {
    _speechAvailable = await _speech.initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await context.read<VoiceService>().speak(
          'Ab ek bharosemand insaan ka number daalein. '
          'Naam bolo ya neeche se chunein.',
        );
  }

  List<Map<String, String>> get _filtered {
    if (_query.isEmpty) return _mockContacts;
    final q = _query.toLowerCase();
    return _mockContacts
        .where((c) =>
            c['name']!.toLowerCase().contains(q) ||
            c['phone']!.contains(q))
        .toList();
  }

  void _startVoiceSearch() {
    if (!_speechAvailable) return;
    setState(() => _isListening = true);
    _speech.listen(
      localeId: 'hi_IN',
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        if (result.finalResult) {
          setState(() {
            _isListening = false;
            _query = result.recognizedWords;
            _searchCtrl.text = _query;
          });
          _tryVoiceMatch(result.recognizedWords);
        }
      },
    );
  }

  void _tryVoiceMatch(String spoken) {
    final q = spoken.toLowerCase();
    final match = _mockContacts.firstWhere(
      (c) => c['name']!.toLowerCase().contains(q.split(' ').first),
      orElse: () => {},
    );
    if (match.isNotEmpty) {
      _showConfirmation(match);
    }
  }

  void _showConfirmation(Map<String, String> contact) {
    setState(() => _pendingContact = contact);
    final name = contact['name']!;
    final firstName = name.split(' ').first;
    context.read<VoiceService>().speak(
          '$firstName mili. Kya yahi hain?',
        );
  }

  Future<void> _confirmGuardian() async {
    if (_pendingContact == null) return;
    context.read<SetupNotifier>().setGuardian(_pendingContact!);
    setState(() => _confirmed = true);
    await context.read<VoiceService>().speak(
          '${_pendingContact!['name']!.split(' ').first} ko guardian banaya. Bahut acha!',
        );
    await Future.delayed(const Duration(milliseconds: 1600));
    if (mounted) Navigator.pushReplacementNamed(context, '/setup/language');
  }

  Future<void> _skip() async {
    await context.read<VoiceService>().speak('Theek hai, baad mein add kar sakte hain.');
    if (mounted) Navigator.pushReplacementNamed(context, '/setup/language');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: SetupStep.guardian,
      title: 'Guardian Chunein',
      subtitle: 'Ek bharosemand insaan jo emergency mein help kare.',
      icon: _GuardianIcon(confirmed: _confirmed),
      body: _pendingContact != null && !_confirmed
          ? _ConfirmCard(
              contact: _pendingContact!,
              onConfirm: _confirmGuardian,
              onDeny: () => setState(() {
                _pendingContact = null;
                _searchCtrl.clear();
              }),
            )
          : _confirmed
              ? _SuccessCard(contact: _pendingContact!)
              : Column(
                  children: [
                    // Voice search bar
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(color: AppColors.white),
                            decoration: InputDecoration(
                              hintText: 'Naam type karein...',
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: AppColors.textMuted),
                              filled: true,
                              fillColor: AppColors.navyCard,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSizes.buttonRadius),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppSizes.buttonRadius),
                                borderSide: const BorderSide(
                                    color: AppColors.saffron, width: 2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        // Mic button
                        Semantics(
                          label: 'Naam bolke dhundhein',
                          child: GestureDetector(
                            onTap: _startVoiceSearch,
                            child: AnimatedContainer(
                              duration: AppDurations.medium,
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isListening
                                    ? AppColors.saffron
                                    : AppColors.navyCard,
                                border: Border.all(
                                  color: _isListening
                                      ? AppColors.saffronLight
                                      : AppColors.navyLight,
                                ),
                              ),
                              child: Icon(
                                _isListening
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded,
                                color: _isListening
                                    ? AppColors.navyDeep
                                    : AppColors.saffron,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),

                    // Contact list
                    ..._filtered.map(
                      (contact) => _ContactTile(
                        contact: contact,
                        onTap: () => _showConfirmation(contact),
                      ),
                    ),

                    const SizedBox(height: AppSizes.lg),

                    // Skip
                    Semantics(
                      label: 'Baad mein guardian add karein',
                      child: OutlinedButton(
                        onPressed: _skip,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(
                              double.infinity, AppSizes.minTouchTarget),
                          side:
                              const BorderSide(color: AppColors.navyLight),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppSizes.buttonRadius)),
                        ),
                        child: const Text('Baad mein add karein',
                            style:
                                TextStyle(color: AppColors.textMuted)),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _GuardianIcon extends StatelessWidget {
  final bool confirmed;
  const _GuardianIcon({this.confirmed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: confirmed
              ? [
                  AppColors.safeGreen.withValues(alpha: 0.3),
                  AppColors.safeGreen.withValues(alpha: 0.08),
                ]
              : [
                  AppColors.saffronLight.withValues(alpha: 0.25),
                  AppColors.saffron.withValues(alpha: 0.08),
                ],
        ),
        border: Border.all(
          color: confirmed
              ? AppColors.safeGreen.withValues(alpha: 0.5)
              : AppColors.saffron.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Icon(
        confirmed ? Icons.shield_rounded : Icons.person_search_rounded,
        size: 56,
        color: confirmed ? AppColors.safeGreen : AppColors.saffron,
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          end: 1.08,
          duration: 2000.ms,
          curve: Curves.easeInOut,
        );
  }
}

class _ContactTile extends StatelessWidget {
  final Map<String, String> contact;
  final VoidCallback onTap;
  const _ContactTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Select ${contact['name']} as guardian',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSizes.sm),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md, vertical: AppSizes.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.navyCard,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.saffron.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(
                    contact['initials']!,
                    style: const TextStyle(
                      color: AppColors.saffron,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact['name']!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(contact['phone']!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  final Map<String, String> contact;
  final VoidCallback onConfirm;
  final VoidCallback onDeny;
  const _ConfirmCard(
      {required this.contact,
      required this.onConfirm,
      required this.onDeny});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Contact card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.saffron.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(
                color: AppColors.saffron.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.saffron.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: Text(contact['initials']!,
                      style: const TextStyle(
                          color: AppColors.saffron,
                          fontWeight: FontWeight.w800,
                          fontSize: 20)),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact['name']!,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 18)),
                    Text(contact['phone']!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.1, end: 0),
        const SizedBox(height: AppSizes.lg),

        Text(
          'Kya yahi hain aapke guardian?',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSizes.lg),

        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
              minimumSize:
                  const Size(double.infinity, AppSizes.minTouchTarget)),
          child: const Text('Haan, Yahi Hain ✓'),
        ),
        const SizedBox(height: AppSizes.md),
        OutlinedButton(
          onPressed: onDeny,
          style: OutlinedButton.styleFrom(
            minimumSize:
                const Size(double.infinity, AppSizes.minTouchTarget),
            side: const BorderSide(color: AppColors.navyLight),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppSizes.buttonRadius)),
          ),
          child: const Text('Nahi, Dobara Dhundhein',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      ],
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final Map<String, String> contact;
  const _SuccessCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.xl),
      decoration: BoxDecoration(
        color: AppColors.safeGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border:
            Border.all(color: AppColors.safeGreen.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.shield_rounded,
              color: AppColors.safeGreen, size: 48),
          const SizedBox(height: AppSizes.md),
          Text('${contact['name']} Guardian Ban Gaye!',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.safeGreen),
              textAlign: TextAlign.center),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scaleXY(begin: 0.9, end: 1.0);
  }
}
