import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../services/audio_recorder_service.dart';
import '../../state/language_provider.dart';
import '../../state/patient_data_provider.dart';
import '../../widgets/bilingual_text.dart';
import 'quick_checkin_screen.dart';
import 'result_screen.dart';

/// Voice Diary — POST /entries with entry_type=voice + raw_transcript.
///
/// Speech-to-text: `speech_to_text` (on-device recognition via the OS's
/// own speech engine on Android/iOS/web) — see context/decisions-log.md for
/// why this package. The language toggle changes the recognition locale
/// (see LanguageProvider.speechLocaleId), so it genuinely affects what gets
/// sent to voice entry processing, not just this screen's static labels —
/// per the task's explicit requirement.
///
/// `speech_to_text` has no Linux-desktop backend, so on this session's
/// verification platform (`flutter run -d linux`) the mic button correctly
/// reports itself unavailable and the screen falls back to the same
/// "Type instead" text field the prototype offers as a first-class
/// alternative (its own copy: "If speech is unavailable, typing works
/// exactly the same way") — both paths call the identical
/// POST /entries(entry_type=voice). See context/decisions-log.md for what
/// was and wasn't verified this way.
///
/// Acoustic-analysis audio capture runs SEQUENTIALLY, right after
/// speech_to_text's session ends (see `_captureFollowUpAudioSampleOnce`)
/// — not concurrently with it. Real-device testing (2026-08-27) confirmed
/// running both at once starves the recognizer of mic input entirely on
/// at least one real device; see context/decisions-log.md for the full
/// root-cause writeup and why the two can't be truly simultaneous given
/// speech_to_text's live-mic-only API (no file transcription, no captured-
/// audio export).
class VoiceDiaryScreen extends StatefulWidget {
  const VoiceDiaryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<VoiceDiaryScreen> createState() => _VoiceDiaryScreenState();
}

class _VoiceDiaryScreenState extends State<VoiceDiaryScreen> {
  final _speech = stt.SpeechToText();
  final _typedCtrl = TextEditingController();
  // Raw audio capture for acoustic analysis — see
  // lib/services/audio_recorder_service.dart and context/decisions-log.md
  // (2026-08-27 fix, superseding the original 2026-08-25 concurrent
  // design) for why this now runs SEQUENTIALLY, immediately after
  // speech_to_text's session ends, rather than at the same time as it.
  final _recorder = AudioRecorderService();
  String? _recordedAudioPath;

  bool _speechAvailable = false;
  bool _speechChecked = false;
  bool _listening = false;
  bool _typeInstead = false;
  bool _submitting = false;
  String _transcript = '';
  // Diagnostic-only state (added 2026-08-27, real-device verification pass —
  // see context/decisions-log.md) so a recognition failure is VISIBLE
  // instead of looking identical to "still working." speech_to_text's
  // onError previously discarded the error entirely.
  String? _lastRecognitionError;

  // Sequential follow-up audio capture (2026-08-27 fix — see
  // decisions-log.md). Runs once per listen session, only after
  // speech_to_text has fully released the mic. Fixed duration rather than
  // an open-ended recording: long enough to comfortably clear the
  // backend's own MIN_DURATION_FOR_FLAG_SECONDS=3.0 threshold
  // (app/services/audio_analysis.py) for a trustworthy acoustic reading,
  // short enough not to make the user wait around after they're already
  // done speaking.
  static const _followUpSampleDuration = Duration(seconds: 6);
  bool _capturingSample = false;
  bool _followUpCaptureTriggered = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = false;
    try {
      available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _listening = false);
            // Covers auto-stop (recognizer times out on silence) in
            // addition to the manual-stop path in _toggleListening() below
            // — either way, the mic is free the moment this fires, which
            // is exactly when the follow-up sample is allowed to start.
            // Guarded so it only ever runs once per session regardless of
            // which path triggers it first.
            unawaited(_captureFollowUpAudioSampleOnce());
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _listening = false;
              _lastRecognitionError = error.errorMsg;
            });
          }
        },
      );
    } catch (_) {
      available = false;
    }
    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _speechChecked = true;
        // No usable mic engine on this platform — go straight to typing,
        // matching the prototype's own documented fallback behavior.
        _typeInstead = !available;
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
        // onError doesn't always fire on a manual stop with zero
        // recognized words (e.g. a genuine no-match) — surface that case
        // too instead of leaving it looking identical to success.
        if (_transcript.trim().isEmpty && _lastRecognitionError == null) {
          _lastRecognitionError = 'no_speech_recognized';
        }
      });
      // Also covers the manual-stop path — the onStatus 'notListening'/
      // 'done' callback normally fires from this too, but that's an async
      // native callback with no ordering guarantee relative to this
      // await, so this call is here too. Guarded against double-firing.
      unawaited(_captureFollowUpAudioSampleOnce());
      return;
    }
    final localeId = context.read<LanguageProvider>().speechLocaleId;
    setState(() {
      _listening = true;
      _transcript = '';
      _recordedAudioPath = null;
      _lastRecognitionError = null;
      _followUpCaptureTriggered = false;
    });
    await _speech.listen(
      onResult: (result) {
        setState(() => _transcript = result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(localeId: localeId),
    );
  }

  /// Sequential audio capture for acoustic analysis — see decisions-log.md
  /// (2026-08-27 fix). Only ever called after speech_to_text has released
  /// the mic (see the two call sites above), never while `_listening` is
  /// still true. Best-effort throughout: any failure just leaves
  /// `_recordedAudioPath` null, exactly as before — Voice Diary's
  /// transcript-and-submit path is completely unaffected either way.
  Future<void> _captureFollowUpAudioSampleOnce() async {
    if (_followUpCaptureTriggered) {
      debugPrint('_captureFollowUpAudioSampleOnce: already triggered, skipping');
      return;
    }
    _followUpCaptureTriggered = true;
    debugPrint('_captureFollowUpAudioSampleOnce: starting follow-up recorder');
    if (mounted) setState(() => _capturingSample = true);
    final started = await _recorder.start();
    debugPrint('_captureFollowUpAudioSampleOnce: recorder.start() returned $started');
    if (started) {
      await Future.delayed(_followUpSampleDuration);
    }
    final path = await _recorder.stop();
    debugPrint('_captureFollowUpAudioSampleOnce: recorder.stop() returned $path');
    if (mounted) {
      setState(() {
        _recordedAudioPath = path;
        _capturingSample = false;
      });
    } else {
      _recordedAudioPath = path;
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    _typedCtrl.dispose();
    super.dispose();
  }

  String get _finalTranscript => _typeInstead ? _typedCtrl.text.trim() : _transcript.trim();

  Future<void> _analyze() async {
    final transcript = _finalTranscript;
    if (transcript.isEmpty) return;
    setState(() => _submitting = true);
    try {
      var entry = await context.read<PatientDataProvider>().submitEntry(
            entryType: 'voice',
            rawTranscript: transcript,
            medicineStatus: 'taken',
          );
      // Upload the raw recording alongside the just-submitted entry (see
      // context/decisions-log.md, 2026-08-25) — a SEPARATE call after
      // POST /entries, not merged into it, so any failure here can never
      // affect the entry or risk_result already returned above. If it
      // succeeds and the acoustic signal changed the risk evaluation, the
      // Result screen below shows the updated version.
      final audioPath = _recordedAudioPath;
      debugPrint('_analyze: _recordedAudioPath at submit time = $audioPath');
      if (audioPath != null && mounted) {
        final updated = await context.read<PatientDataProvider>().attachAudio(
              entryId: entry.id,
              filePath: audioPath,
            );
        if (updated != null) entry = updated;
      }
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(entry: entry)));
      setState(() {
        _transcript = '';
        _typedCtrl.clear();
        _recordedAudioPath = null;
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reset() {
    setState(() {
      _transcript = '';
      _typedCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Blocked during _capturingSample too — the follow-up recording (see
    // _captureFollowUpAudioSampleOnce) needs the mic to itself for its
    // fixed window, and submitting before it finishes would mean this
    // entry ships without _recordedAudioPath set yet.
    // ALSO blocked while _listening (2026-08-28 fix — see
    // context/decisions-log.md): this previously didn't check _listening
    // at all, so the button was tappable as soon as ANY partial transcript
    // existed — including while the user was still actively speaking,
    // before the follow-up capture had even been triggered. A real device
    // test reproduced exactly this: submitEntry() completed with
    // _recordedAudioPath still null because the follow-up recorder hadn't
    // started (or had only just started) yet. Requiring !_listening means
    // the user must stop the mic first, which is the ONLY point that
    // actually triggers the follow-up capture sequence — closing the gap
    // entirely rather than narrowing a timing window.
    final canAnalyze =
        _finalTranscript.isNotEmpty && !_submitting && !_capturingSample && !_listening;

    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const BilingualText(
            en: 'Tell us in your own words',
            ur: 'Apni baat kahiye',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          if (!_typeInstead)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
                child: Column(
                  children: [
                    GestureDetector(
                      // Also blocked during _capturingSample — starting a
                      // new listen() session while the sequential
                      // follow-up recorder still holds the mic would
                      // recreate the exact contention this fix removed.
                      onTap: _speechAvailable && !_capturingSample ? _toggleListening : null,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: RnColors.accent, width: 1.5),
                          color: (_listening || _capturingSample) ? RnColors.accent100 : null,
                        ),
                        child: Icon(
                          _listening ? Icons.stop : Icons.mic_none,
                          size: 46,
                          color: RnColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      !_speechChecked
                          ? 'Checking microphone…'
                          : _capturingSample
                              ? 'Capturing voice sample for analysis…'
                              : (_listening ? 'Listening…' : 'Tap to speak'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    if (_capturingSample) ...[
                      const SizedBox(height: 4),
                      // Sequential-capture fix (2026-08-27, see
                      // decisions-log.md) — this is the recorder's short
                      // fixed-duration follow-up sample, taken right after
                      // the transcript above finished, not spoken audio of
                      // that transcript itself. Said plainly here since a
                      // silent few-second wait with no explanation would
                      // just look like the app hanging.
                      Text(
                        'A short voice sample for the acoustic signal (fatigue/breathlessness) is recorded right after you finish speaking — this is separate from the transcript above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: context.rnMuted(0.55)),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // Diagnostic-only, added 2026-08-27 (see decisions-log.md)
                    // — makes the active recognition locale visible, since it
                    // comes from the account's stored language preference on
                    // login, not the phone's own language, and a mismatch
                    // (e.g. speaking English while set to ur-PK) can silently
                    // produce zero results.
                    Text(
                      'Recognition locale: ${context.watch<LanguageProvider>().speechLocaleId}',
                      style: TextStyle(fontSize: 11, color: context.rnMuted(0.55)),
                    ),
                    if (_lastRecognitionError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _lastRecognitionError == 'no_speech_recognized'
                            ? 'No speech was recognized. Check the recognition locale above matches the language you spoke, then try again — or use "Type here instead."'
                            : 'Recognition error: $_lastRecognitionError. Try again, or use "Type here instead."',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: RnColors.riskRed, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (!_typeInstead) const SizedBox(height: 20),
          if (!_typeInstead)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LIVE TRANSCRIPT', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: RnColors.accent)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        _transcript.isEmpty ? '—' : _transcript,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TYPE YOUR ENTRY', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: RnColors.accent)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _typedCtrl,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: context.watch<LanguageProvider>().isRomanUrdu
                            ? 'Masalan: seene mein dard hai...'
                            : 'e.g. I have chest pain today...',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: canAnalyze ? _analyze : null,
            child: _submitting
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save & analyse this entry'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QuickCheckinScreen()),
                  ),
                  child: const Text('Type instead — full check-in'),
                ),
              ),
              const SizedBox(width: 10),
              if (_speechAvailable)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _typeInstead = !_typeInstead),
                    child: Text(_typeInstead ? 'Use microphone' : 'Type here instead'),
                  ),
                ),
            ],
          ),
          TextButton(onPressed: _reset, child: const Text('Start over')),
          const SizedBox(height: 8),
          Text(
            'Speech is converted to text on your device where supported. '
            'If speech is unavailable, typing works exactly the same way.',
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: context.rnMuted(0.55)),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voice Diary'), actions: const [_LanguageToggleAction()]),
        body: body,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Diary'), actions: const [_LanguageToggleAction()]),
      body: body,
    );
  }
}

class _LanguageToggleAction extends StatelessWidget {
  const _LanguageToggleAction();

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    // Bug fix (2026-08-27, real-device verification — see decisions-log.md):
    // this previously showed the language you'd SWITCH TO ('EN' while
    // Roman Urdu was active), which reads exactly like "EN is currently
    // selected" even though the underlying state (and the recognition
    // locale it drives) was correct the whole time. Show the CURRENTLY
    // active language instead, so what's on screen matches what
    // speech_to_text.listen() is actually using.
    return TextButton(
      onPressed: () => lang.toggle(),
      child: Text(
        lang.isRomanUrdu ? 'اردو' : 'EN',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
