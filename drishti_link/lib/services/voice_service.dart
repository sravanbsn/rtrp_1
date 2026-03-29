import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { playing, stopped, paused }

/// Drishti's voice — calm, motherly, Hinglish.
/// Singleton ChangeNotifier so any widget can trigger speech.
class VoiceService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();
  TtsState _state = TtsState.stopped;
  String _currentText = '';

  TtsState get state => _state;
  String get currentText => _currentText;
  bool get isSpeaking => _state == TtsState.playing;

  VoiceService() {
    _initTts();
  }

  Future<void> _initTts() async {
    // Language — prefer hi-IN (Hindi), fallback en-IN
    final languages = await _tts.getLanguages as List<dynamic>? ?? [];
    final hasHindi = languages.any((l) => l.toString().contains('hi'));
    await _tts.setLanguage(hasHindi ? 'hi-IN' : 'en-IN');

    // Voice quality: calm, deliberate pace
    await _tts.setSpeechRate(0.42);  // Slower = clearer for visually impaired
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.95);       // Slightly lower = warmer, motherly

    // iOS: allow TTS over silent mode
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
    );

    _tts.setStartHandler(() {
      _state = TtsState.playing;
      notifyListeners();
    });

    _tts.setCompletionHandler(() {
      _state = TtsState.stopped;
      notifyListeners();
    });

    _tts.setCancelHandler(() {
      _state = TtsState.stopped;
      notifyListeners();
    });

    _tts.setErrorHandler((msg) {
      _state = TtsState.stopped;
      notifyListeners();
      debugPrint('Drishti TTS error: $msg');
    });
  }

  /// Speak [text]. Cancels any in-progress speech first.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (_state == TtsState.playing) {
      await _tts.stop();
    }
    _currentText = text;
    notifyListeners();
    await _tts.speak(text);
  }

  /// Immediately silence Drishti.
  Future<void> stop() async {
    await _tts.stop();
    _state = TtsState.stopped;
    _currentText = '';
    notifyListeners();
  }

  /// Re-speak the last utterance (e.g., user tapped voice bar).
  Future<void> repeat() async {
    if (_currentText.isNotEmpty) {
      await speak(_currentText);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
