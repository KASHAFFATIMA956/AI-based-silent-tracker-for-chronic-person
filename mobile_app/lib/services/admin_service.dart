import '../core/api_client.dart';
import '../models/admin_user.dart';

/// GET/POST /admin/users, PATCH /admin/users/{id} — see
/// context/api-contracts.md. All three are admin-only backend-side; RBAC is
/// enforced there, not here (same convention as every other *Service class
/// in this app — a thin wrapper, no business logic of its own).
class AdminService {
  final _dio = ApiClient.instance.dio;

  Future<List<AdminUser>> getUsers() {
    return ApiClient.instance.run(() async {
      final res = await _dio.get('/admin/users');
      return (res.data as List<dynamic>)
          .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Creates a user of any role. Reuses the backend's existing real
  /// bcrypt-hashing flow (`app.core.security.hash_password`) — this call
  /// just sends the plaintext password over HTTPS/the API the same way
  /// login does; no hashing happens client-side.
  Future<AdminUser> createUser({
    required String name,
    required String role,
    required String phoneOrEmail,
    required String password,
    required String languagePreference,
  }) {
    return ApiClient.instance.run(() async {
      final res = await _dio.post('/admin/users', data: {
        'name': name,
        'role': role,
        'phone_or_email': phoneOrEmail,
        'password': password,
        'language_preference': languagePreference,
      });
      return AdminUser.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// Partial edit — only the fields the backend actually supports
  /// (name/role/phone_or_email/language_preference). No `status` field:
  /// `users` has no such column (see context/decisions-log.md). Pass only
  /// the fields that changed; [AdminUserUpdate]'s own validator 422s on an
  /// entirely-empty body, so callers must never invoke this with nothing
  /// changed.
  Future<AdminUser> updateUser(
    int userId, {
    String? name,
    String? role,
    String? phoneOrEmail,
    String? languagePreference,
  }) {
    return ApiClient.instance.run(() async {
      final body = <String, dynamic>{
        if (name != null) 'name': name,
        if (role != null) 'role': role,
        if (phoneOrEmail != null) 'phone_or_email': phoneOrEmail,
        if (languagePreference != null) 'language_preference': languagePreference,
      };
      final res = await _dio.patch('/admin/users/$userId', data: body);
      return AdminUser.fromJson(res.data as Map<String, dynamic>);
    });
  }
}
