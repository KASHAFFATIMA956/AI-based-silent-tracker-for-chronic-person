import '../core/api_client.dart';
import '../models/message.dart';

/// GET/POST /patients/{patient_id}/messages — direct messaging between a
/// patient (or their attendant) and their assigned doctor. Added
/// 2026-09-07 — see context/api-contracts.md. Kept in its own file rather
/// than folded into PatientService since it's a large enough standalone
/// feature (a whole chat screen, polled on an interval) to warrant one,
/// mirroring the backend's own separate app/routers/messages.py.
class MessageService {
  final _dio = ApiClient.instance.dio;

  Future<List<Message>> getMessages(int patientId) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/patients/$patientId/messages');
      return (res.data as List<dynamic>)
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Message> sendMessage(int patientId, String content) {
    return ApiClient.instance.run(() async {
      final res = await _dio.post('/patients/$patientId/messages', data: {'content': content});
      return Message.fromJson(res.data as Map<String, dynamic>);
    });
  }
}
