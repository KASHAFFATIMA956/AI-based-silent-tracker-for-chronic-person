/// Decoded shape of a successful POST /auth/login (context/api-contracts.md)
/// plus the patient_id enrichment GET /auth/me now also returns (added this
/// pass — see context/decisions-log.md). Role is read verbatim from the
/// backend/JWT and is the ONLY thing that decides post-login routing —
/// never a user selection. See lib/state/auth_provider.dart.
class AuthSession {
  AuthSession({
    required this.token,
    required this.userId,
    required this.role,
    required this.name,
    this.patientId,
    this.languagePreference,
  });

  final String token;
  final int userId;
  final String role; // "patient" | "attendant" | "doctor" | "admin"
  final String name;
  final int? patientId;
  final String? languagePreference; // "english" | "roman_urdu"

  bool get isPatientOrAttendant => role == 'patient' || role == 'attendant';

  AuthSession copyWith({int? patientId, String? languagePreference}) {
    return AuthSession(
      token: token,
      userId: userId,
      role: role,
      name: name,
      patientId: patientId ?? this.patientId,
      languagePreference: languagePreference ?? this.languagePreference,
    );
  }
}
