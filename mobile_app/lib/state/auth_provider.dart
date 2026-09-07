import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/secure_storage.dart';
import '../models/auth_session.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Owns the current session. `role` on [session] is the ONLY signal any
/// routing decision uses (see context/decisions-log.md — role-switcher
/// tabs were removed for exactly this reason: routing must never be a user
/// choice). Session state persists via SecureStorageService so the app
/// stays signed in across restarts; [restoreSession] is called once at
/// startup before the router decides what to show.
class AuthProvider extends ChangeNotifier {
  final _authService = AuthService();

  AuthStatus status = AuthStatus.unknown;
  AuthSession? session;
  String? lastError;

  Future<void> restoreSession() async {
    try {
      final stored = await SecureStorageService.instance.readSession();
      if (stored == null) {
        status = AuthStatus.signedOut;
        notifyListeners();
        return;
      }
      // Token exists locally — confirm it's still valid (not expired/
      // revoked) and pick up patient_id + language_preference via a real
      // /auth/me call rather than trusting the locally-cached role blindly.
      final base = AuthSession(
        token: stored['token']!,
        userId: int.parse(stored['userId']!),
        role: stored['role']!,
        name: stored['name']!,
      );
      session = await _authService.fetchMe(base);
      status = AuthStatus.signedIn;
    } catch (_) {
      // Covers both an expired/invalid token AND the secure storage plugin
      // being unavailable (e.g. no platform channel in a widget test) —
      // either way, fail safe to the login screen rather than an infinite
      // splash.
      await SecureStorageService.instance.clear().catchError((_) {});
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> login(String phoneOrEmail, String password) async {
    lastError = null;
    notifyListeners();
    try {
      var newSession = await _authService.login(
        phoneOrEmail: phoneOrEmail,
        password: password,
      );
      await SecureStorageService.instance.saveSession(
        token: newSession.token,
        userId: newSession.userId,
        role: newSession.role,
        name: newSession.name,
      );
      // Resolve patient_id + language_preference immediately so every
      // downstream screen has them without a second round trip.
      newSession = await _authService.fetchMe(newSession);
      session = newSession;
      status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      status = AuthStatus.signedOut;
      notifyListeners();
      return false;
    } catch (_) {
      lastError = 'Something went wrong. Please try again.';
      status = AuthStatus.signedOut;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await SecureStorageService.instance.clear();
    session = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
