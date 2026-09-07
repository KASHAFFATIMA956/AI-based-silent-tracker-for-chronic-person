import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../models/entry.dart';

/// POST /entries and GET /entries/{patient_id}/timeline — see
/// context/api-contracts.md. `EntryCreate` mirrors app/schemas/entry.py's
/// request shape exactly (same field names, same null-omission behavior).
class EntryService {
  final _dio = ApiClient.instance.dio;

  Future<Entry> submitEntry({
    required int patientId,
    required String entryType, // "voice" | "quick"
    String? rawTranscript,
    double? sleepValue,
    double? energyValue,
    double? moodValue,
    double? appetiteValue,
    double? mobilityValue,
    double? weightValue,
    int? systolicBp,
    int? diastolicBp,
    int? bloodSugarMgDl,
    required String medicineStatus, // "taken" | "missed"
    List<int> symptomIds = const [],
  }) {
    return ApiClient.instance.run(() async {
      final res = await _dio.post('/entries', data: {
        'patient_id': patientId,
        'entry_type': entryType,
        if (rawTranscript != null) 'raw_transcript': rawTranscript,
        if (sleepValue != null) 'sleep_value': sleepValue,
        if (energyValue != null) 'energy_value': energyValue,
        if (moodValue != null) 'mood_value': moodValue,
        if (appetiteValue != null) 'appetite_value': appetiteValue,
        if (mobilityValue != null) 'mobility_value': mobilityValue,
        if (weightValue != null) 'weight_value': weightValue,
        // Added 2026-09-07 — optional home-monitoring readings, same
        // null-omission contract as every other optional field above.
        // Persisted only — see context/api-contracts.md.
        if (systolicBp != null) 'systolic_bp': systolicBp,
        if (diastolicBp != null) 'diastolic_bp': diastolicBp,
        if (bloodSugarMgDl != null) 'blood_sugar_mg_dl': bloodSugarMgDl,
        'medicine_status': medicineStatus,
        'symptom_ids': symptomIds,
      });
      return Entry.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// POST /entries/{entry_id}/audio — attaches a raw Voice Diary recording
  /// to an already-created voice entry for backend acoustic-signal
  /// analysis. See context/api-contracts.md and context/decisions-log.md
  /// (2026-08-25, acoustic-analysis pass) for why this is a separate call
  /// from submitEntry rather than merged into it — callers should treat
  /// failure here as non-fatal (the entry and its transcript-based
  /// risk_result already exist regardless).
  Future<Entry> uploadAudio({required int entryId, required String filePath}) {
    return ApiClient.instance.run(() async {
      final formData = FormData.fromMap({
        'audio_file': await MultipartFile.fromFile(filePath),
      });
      // Explicit multipart content-type: ApiClient's shared Dio instance
      // defaults every request to application/json (see api_client.dart) —
      // without overriding it here, FormData would still get sent with
      // the wrong Content-Type header and FastAPI would reject the body.
      final res = await _dio.post(
        '/entries/$entryId/audio',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return Entry.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<List<Entry>> getTimeline(int patientId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/entries/$patientId/timeline');
      return (res.data as List<dynamic>)
          .map((e) => Entry.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}
