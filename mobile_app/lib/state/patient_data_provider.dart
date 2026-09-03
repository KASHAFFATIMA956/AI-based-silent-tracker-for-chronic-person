import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/entry.dart';
import '../models/patient_profile.dart';
import '../services/entry_service.dart';
import '../services/patient_service.dart';

/// Holds every piece of "real" patient data the patient screens render —
/// profile, symptom checklist, and timeline — fetched from the FastAPI
/// backend. Replaces the mock/local JSON the screens started from (this
/// session's task). One provider shared across the patient shell so
/// submitting an entry on Voice Diary / Quick Check-in immediately updates
/// what Home/Timeline/Weekly Digest show, without each screen re-fetching
/// independently. See context/conventions.md.
class PatientDataProvider extends ChangeNotifier {
  final _patientService = PatientService();
  final _entryService = EntryService();

  int? _patientId;

  PatientProfile? profile;
  List<SymptomOption> symptomChecklist = [];
  List<Entry> timeline = [];

  bool isLoading = false;
  String? loadError;

  Entry? get latestEntry => timeline.isEmpty ? null : timeline.first;

  Future<void> loadAll(int patientId) async {
    _patientId = patientId;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _patientService.getPatient(patientId),
        _patientService.getSymptomChecklist(patientId),
        _entryService.getTimeline(patientId),
      ]);
      profile = results[0] as PatientProfile;
      symptomChecklist = results[1] as List<SymptomOption>;
      timeline = results[2] as List<Entry>;
    } on ApiException catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = 'Could not load your data right now.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshTimeline() async {
    if (_patientId == null) return;
    try {
      timeline = await _entryService.getTimeline(_patientId!);
      notifyListeners();
    } catch (_) {
      // Timeline refresh failures stay silent here — the caller (Timeline
      // screen) shows its own retry affordance; this just avoids clobbering
      // already-loaded data with an error state on a background refresh.
    }
  }

  /// Submits an entry, then refreshes the timeline so Home/Timeline/Digest
  /// reflect it immediately. Returns the created Entry (with its
  /// risk_result) for the Result screen to display.
  Future<Entry> submitEntry({
    required String entryType,
    String? rawTranscript,
    double? sleepValue,
    double? energyValue,
    double? moodValue,
    double? appetiteValue,
    double? mobilityValue,
    double? weightValue,
    required String medicineStatus,
    List<int> symptomIds = const [],
  }) async {
    if (_patientId == null) {
      throw StateError('PatientDataProvider.loadAll must be called first');
    }
    final entry = await _entryService.submitEntry(
      patientId: _patientId!,
      entryType: entryType,
      rawTranscript: rawTranscript,
      sleepValue: sleepValue,
      energyValue: energyValue,
      moodValue: moodValue,
      appetiteValue: appetiteValue,
      mobilityValue: mobilityValue,
      weightValue: weightValue,
      medicineStatus: medicineStatus,
      symptomIds: symptomIds,
    );
    await refreshTimeline();
    // day_count/baseline_stage may have advanced server-side — refresh the
    // profile too so the Profile screen's baseline progress stays accurate.
    if (_patientId != null) {
      try {
        profile = await _patientService.getPatient(_patientId!);
      } catch (_) {
        // Non-fatal — the just-submitted entry's own result still returns
        // below even if this refresh fails.
      }
    }
    notifyListeners();
    return entry;
  }

  /// Attaches a locally-recorded Voice Diary audio file to an
  /// already-submitted voice entry (POST /entries/{id}/audio), then
  /// refreshes the timeline so the (possibly acoustic-signal-updated)
  /// risk_result shows everywhere. Best-effort by design — see
  /// context/decisions-log.md (2026-08-25): a failure here (recording
  /// missing, upload error, analysis error) must never surface as a
  /// broken entry, since the entry and its transcript-based risk_result
  /// already exist and are valid on their own. Returns the updated Entry
  /// on success, or null on any failure (swallowed here; caller decides
  /// whether to show anything).
  Future<Entry?> attachAudio({required int entryId, required String filePath}) async {
    try {
      final updated = await _entryService.uploadAudio(entryId: entryId, filePath: filePath);
      await refreshTimeline();
      if (_patientId != null) {
        try {
          profile = await _patientService.getPatient(_patientId!);
        } catch (_) {
          // Non-fatal, same as submitEntry's profile refresh above.
        }
      }
      notifyListeners();
      return updated;
    } catch (e, st) {
      // DIAGNOSTIC (2026-08-27, real-device verification — see
      // decisions-log.md): this catch previously discarded the exception
      // entirely (`catch (_)`), which is correct for the soft-fail
      // CONTRACT (never surface to the user, never block the entry) but
      // made a real upload failure indistinguishable from "nothing went
      // wrong" during debugging — a genuine recording (confirmed present
      // and correctly sized on-device) silently never reached the
      // backend, with zero trace anywhere. Logging only, still returns
      // null exactly as before — the soft-fail behavior itself is
      // unchanged.
      debugPrint('attachAudio failed (entry $entryId, file $filePath): $e\n$st');
      return null;
    }
  }

  void reset() {
    _patientId = null;
    profile = null;
    symptomChecklist = [];
    timeline = [];
    isLoading = false;
    loadError = null;
  }
}
