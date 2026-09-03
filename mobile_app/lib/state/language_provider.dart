import 'package:flutter/foundation.dart';

/// English / Roman Urdu toggle. Initialized from the account's
/// `language_preference` (GET /auth/me) on login, then freely toggleable
/// in-session — there is no PATCH endpoint to persist a change back to the
/// account, so a toggle here only affects THIS session's UI text and voice
/// recognition locale, not the stored preference. Flagged in
/// context/decisions-log.md.
class LanguageProvider extends ChangeNotifier {
  bool isRomanUrdu = false;

  void setFromAccountPreference(String? preference) {
    isRomanUrdu = preference == 'roman_urdu';
    notifyListeners();
  }

  void toggle() {
    isRomanUrdu = !isRomanUrdu;
    notifyListeners();
  }

  void setRomanUrdu(bool value) {
    isRomanUrdu = value;
    notifyListeners();
  }

  /// Locale id passed to speech_to_text — see lib/screens/patient/voice_diary_screen.dart
  /// and context/decisions-log.md (voice diary STT section) for why this is
  /// the mechanism through which the toggle "affects what's sent to voice
  /// entry processing," not just static text.
  String get speechLocaleId => isRomanUrdu ? 'ur-PK' : 'en-US';
}
