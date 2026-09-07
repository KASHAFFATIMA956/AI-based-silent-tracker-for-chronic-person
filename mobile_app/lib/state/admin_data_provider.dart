import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/admin_user.dart';
import '../services/admin_service.dart';

/// Holds the admin "People & roles" list — the smallest remaining role
/// scope in this app (see context/progress.md). Mirrors
/// DoctorDataProvider's shape/conventions: a single `loadAll()` populates
/// the list, `createUser`/`updateUser` update it in place afterward rather
/// than always re-fetching the whole roster.
class AdminDataProvider extends ChangeNotifier {
  final _adminService = AdminService();

  List<AdminUser> users = [];
  bool isLoading = false;
  String? loadError;

  Future<void> loadAll() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      users = await _adminService.getUsers();
    } on ApiException catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = 'Could not load the people list right now.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      users = await _adminService.getUsers();
      notifyListeners();
    } catch (_) {
      // Silent — same convention as DoctorDataProvider.refreshRoster: keep
      // whatever's already shown rather than clobbering it on a background
      // pull-to-refresh.
    }
  }

  /// Lets any ApiException/other error propagate to the caller (the create
  /// form shows it inline) — this is a direct user action, unlike the
  /// silent background refresh above. Appends to the already-loaded list
  /// rather than re-fetching the whole roster.
  Future<AdminUser> createUser({
    required String name,
    required String role,
    required String phoneOrEmail,
    required String password,
    required String languagePreference,
  }) async {
    final created = await _adminService.createUser(
      name: name,
      role: role,
      phoneOrEmail: phoneOrEmail,
      password: password,
      languagePreference: languagePreference,
    );
    users = [...users, created];
    notifyListeners();
    return created;
  }

  /// Same error-propagation convention as createUser. Replaces the edited
  /// row in place so the list reflects the backend's actual computed
  /// `linked_summary`/`diagnosis` for the new role, not a locally-guessed
  /// value.
  Future<AdminUser> updateUser(
    int userId, {
    String? name,
    String? role,
    String? phoneOrEmail,
    String? languagePreference,
  }) async {
    final updated = await _adminService.updateUser(
      userId,
      name: name,
      role: role,
      phoneOrEmail: phoneOrEmail,
      languagePreference: languagePreference,
    );
    final idx = users.indexWhere((u) => u.id == userId);
    if (idx != -1) {
      users[idx] = updated;
    } else {
      users = [...users, updated];
    }
    notifyListeners();
    return updated;
  }

  void reset() {
    users = [];
    isLoading = false;
    loadError = null;
  }
}
