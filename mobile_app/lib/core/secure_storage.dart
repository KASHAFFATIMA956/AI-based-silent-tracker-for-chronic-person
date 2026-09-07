import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT persistence. `flutter_secure_storage` — Keychain on iOS, Keystore-
/// backed EncryptedSharedPreferences on Android — chosen per the task's
/// explicit instruction over plain SharedPreferences, since this stores a
/// bearer token good for 24h (see context/decisions-log.md, auth pass).
/// See context/conventions.md for the Flutter-side conventions summary.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'roznoor_access_token';
  static const _userIdKey = 'roznoor_user_id';
  static const _roleKey = 'roznoor_role';
  static const _nameKey = 'roznoor_name';

  Future<void> saveSession({
    required String token,
    required int userId,
    required String role,
    required String name,
  }) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _userIdKey, value: userId.toString()),
      _storage.write(key: _roleKey, value: role),
      _storage.write(key: _nameKey, value: name),
    ]);
  }

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<Map<String, String>?> readSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return null;
    final userId = await _storage.read(key: _userIdKey);
    final role = await _storage.read(key: _roleKey);
    final name = await _storage.read(key: _nameKey);
    if (userId == null || role == null || name == null) return null;
    return {'token': token, 'userId': userId, 'role': role, 'name': name};
  }

  Future<void> clear() => _storage.deleteAll();
}
