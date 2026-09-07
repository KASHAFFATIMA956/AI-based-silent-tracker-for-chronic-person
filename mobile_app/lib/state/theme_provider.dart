import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paper (light) / Nocturne (dark) toggle — matches the prototype's own
/// theme switch (`RozNoor.dc.html`, "Paper"/"Nocturne" radio pair). Unlike
/// [LanguageProvider], this DOES persist locally (shared_preferences) so
/// the choice survives app restarts, per the task's explicit requirement —
/// a UI display preference has no server-side "account truth" to defer to
/// the way language_preference does, so there's no conflicting source to
/// reconcile on login.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'roznoor_theme_mode';

  ThemeMode _mode = ThemeMode.light;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  bool get isLoaded => _loaded;

  /// Loads the persisted choice, if any. Call once at startup; defaults to
  /// Paper (light) — matching the prototype's own default — when nothing
  /// has been saved yet (first launch, or a restore that fails).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _mode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      // Local-storage failure (rare) — fall back to the light default
      // rather than blocking app startup on it.
      _mode = ThemeMode.light;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDark(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, dark ? 'dark' : 'light');
    } catch (_) {
      // Best-effort persistence — the in-session toggle above already
      // took effect regardless of whether the write succeeds.
    }
  }

  Future<void> toggle() => setDark(_mode != ThemeMode.dark);
}
