import '../core/api_client.dart';
import '../models/auth_session.dart';

/// Wraps POST /auth/login and GET /auth/me. Does NOT re-implement any auth
/// logic (hashing, token verification, etc.) — that's entirely the
/// backend's job (context/decisions-log.md, auth pass). This class only
/// calls the two existing endpoints and shapes the response.
class AuthService {
  final _dio = ApiClient.instance.dio;

  Future<AuthSession> login({
    required String phoneOrEmail,
    required String password,
  }) {
    return ApiClient.instance.run(() async {
      final res = await _dio.post('/auth/login', data: {
        'phone_or_email': phoneOrEmail,
        'password': password,
      });
      final data = res.data as Map<String, dynamic>;
      return AuthSession(
        token: data['access_token'] as String,
        userId: data['user_id'] as int,
        role: data['role'] as String,
        name: data['name'] as String,
      );
    });
  }

  /// Fetches the caller's own identity, including patient_id (see
  /// context/decisions-log.md for why /auth/me now returns that) — called
  /// right after login, and on app-start when a stored token is found, so
  /// the session always carries a resolved patient_id before any
  /// patient-scoped screen tries to use it.
  Future<AuthSession> fetchMe(AuthSession current) {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/auth/me');
      final data = res.data as Map<String, dynamic>;
      return AuthSession(
        token: current.token,
        userId: data['id'] as int,
        role: data['role'] as String,
        name: data['name'] as String,
        patientId: data['patient_id'] as int?,
        languagePreference: data['language_preference'] as String?,
      );
    });
  }
}
