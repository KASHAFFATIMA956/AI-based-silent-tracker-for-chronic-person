import '../core/api_client.dart';
import '../models/doctor.dart';
import '../models/entry.dart';
import '../models/patient_profile.dart';

/// GET /patients/{id}, GET /patients/{id}/symptom-checklist, and
/// POST+GET /patients/{id}/notes — see context/api-contracts.md. The notes
/// methods were added for the doctor role (2026-08-29) — they live here
/// rather than in DoctorService since api-contracts.md groups
/// `/patients/{id}/notes` under its "Patients" section (same URL prefix as
/// the other two methods already here), even though only doctor/admin
/// callers can actually reach them (RBAC enforced backend-side).
class PatientService {
  final _dio = ApiClient.instance.dio;

  Future<PatientProfile> getPatient(int patientId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/patients/$patientId');
      return PatientProfile.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<List<SymptomOption>> getSymptomChecklist(int patientId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/patients/$patientId/symptom-checklist');
      return (res.data as List<dynamic>)
          .map((e) => SymptomOption.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<List<DoctorNote>> getNotes(int patientId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/patients/$patientId/notes');
      return (res.data as List<dynamic>)
          .map((e) => DoctorNote.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<DoctorNote> addNote(int patientId, String noteText) {
    return ApiClient.instance.run(() async {
      final res = await _dio.post('/patients/$patientId/notes', data: {'note_text': noteText});
      return DoctorNote.fromJson(res.data as Map<String, dynamic>);
    });
  }
}
