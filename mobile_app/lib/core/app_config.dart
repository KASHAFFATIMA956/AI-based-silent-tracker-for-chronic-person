/// App-wide config. Single source of truth for the backend base URL —
/// see context/conventions.md for why this isn't scattered across files.
///
/// Defaults to localhost:8000 (this session's verification target: a
/// throwaway local Postgres + `uvicorn app.main:app` on the same machine,
/// tested via `flutter run -d linux`). An Android emulator reaches the
/// host machine at 10.0.2.2, not localhost — swap this constant (or wire
/// up --dart-define) before running on an emulator/device against a local
/// backend. Point this at the real deployed API URL once one exists.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'ROZNOOR_API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
