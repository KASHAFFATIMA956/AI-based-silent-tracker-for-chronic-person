import '../core/api_client.dart';
import '../models/doctor.dart';

/// GET /doctors/{doctor_id}/patients, GET /doctors/{doctor_id}/alerts, and
/// POST /alerts/{alert_id}/review — see context/api-contracts.md. Grouped
/// in one service (rather than a separate one for the `/alerts` route)
/// since all three are one coherent doctor-workflow surface, mirroring
/// app/routers/doctors.py's own two-router-one-file grouping on the
/// backend.
class DoctorService {
  final _dio = ApiClient.instance.dio;

  Future<List<DoctorPatientRosterItem>> getRoster(int doctorId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/doctors/$doctorId/patients');
      return (res.data as List<dynamic>)
          .map((e) => DoctorPatientRosterItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<List<AlertItem>> getAlerts(int doctorId, {bool? reviewed}) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get(
        '/doctors/$doctorId/alerts',
        queryParameters: reviewed == null ? null : {'reviewed': reviewed},
      );
      return (res.data as List<dynamic>)
          .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<AlertItem> reviewAlert(int alertId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.post('/alerts/$alertId/review');
      return AlertItem.fromJson(res.data as Map<String, dynamic>);
    });
  }
}
