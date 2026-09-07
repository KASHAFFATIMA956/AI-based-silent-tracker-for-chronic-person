import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Thin wrapper over the `record` package — captures a raw audio sample
/// for acoustic analysis, run SEQUENTIALLY AFTER speech_to_text's live
/// transcript session ends, not concurrently with it. See
/// context/decisions-log.md (2026-08-27, real-device mic-contention fix)
/// for why: on real hardware, speech_to_text's SpeechRecognizer and this
/// recorder both claiming the mic at once starved the recognizer of audio
/// entirely (confirmed via a real-device diagnostic build, not a guess) —
/// the original 2026-08-25 design ran them concurrently and that risk was
/// flagged as unverified at the time; it has since been verified broken.
/// Every method here stays best-effort regardless: if starting/stopping
/// the recorder fails for any reason (mic busy, permission denied), Voice
/// Diary must still work exactly as before (transcript-only), just
/// without an attached recording for that entry.
class AudioRecorderService {
  final _recorder = AudioRecorder();

  bool _recording = false;
  bool get isRecording => _recording;

  /// Starts recording to a fresh temp file. Returns true if recording
  /// actually started. Never throws — a failure (no mic, mic busy with
  /// speech_to_text, permission denied) is caught and reported as false.
  Future<bool> start() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      // DIAGNOSTIC (2026-08-28, follow-up to the attachAudio silent-catch
      // fix — see context/decisions-log.md): this method had the identical
      // silent-catch shape as the original attachAudio() bug, never
      // instrumented. Logging every branch, not just the catch, since a
      // false `hasPermission` returns false without ever reaching the
      // catch block at all.
      if (!hasPermission) {
        debugPrint('AudioRecorderService.start(): hasPermission() returned false');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/roznoor_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recording = true;
      debugPrint('AudioRecorderService.start(): started, path=$path');
      return true;
    } catch (e, st) {
      debugPrint('AudioRecorderService.start() failed: $e\n$st');
      _recording = false;
      return false;
    }
  }

  /// Stops recording and returns the local file path, or null if nothing
  /// was actually recorded (never started, or stop failed).
  Future<String?> stop() async {
    if (!_recording) {
      debugPrint('AudioRecorderService.stop(): called while not recording, returning null');
      return null;
    }
    try {
      final path = await _recorder.stop();
      _recording = false;
      debugPrint('AudioRecorderService.stop(): stopped, path=$path');
      return path;
    } catch (e, st) {
      debugPrint('AudioRecorderService.stop() failed: $e\n$st');
      _recording = false;
      return null;
    }
  }

  Future<void> dispose() async {
    try {
      if (_recording) await _recorder.stop();
      await _recorder.dispose();
    } catch (_) {
      // best-effort cleanup only
    }
  }
}
