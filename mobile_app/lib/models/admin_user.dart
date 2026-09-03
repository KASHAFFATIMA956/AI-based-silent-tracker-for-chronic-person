/// Mirrors AdminUserOut (app/schemas/admin.py) — see context/api-contracts.md.
/// No `status` field: `users` has no such column and the backend never
/// added one (see context/decisions-log.md) — don't add one here either.
class AdminUser {
  AdminUser({
    required this.id,
    required this.name,
    required this.role,
    required this.phoneOrEmail,
    required this.languagePreference,
    required this.createdAt,
    this.linkedSummary,
    this.diagnosis,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as int,
        name: json['name'] as String,
        role: json['role'] as String,
        phoneOrEmail: json['phone_or_email'] as String,
        languagePreference: json['language_preference'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        linkedSummary: json['linked_summary'] as String?,
        diagnosis: json['diagnosis'] as String?,
      );

  final int id;
  final String name;
  final String role; // patient | attendant | doctor | admin
  final String phoneOrEmail;
  final String languagePreference; // english | roman_urdu
  final DateTime createdAt;
  // Doctor's assigned-patient count, a patient's assigned doctor's name, an
  // attendant's linked patient's name, or "System" for admin — null if not
  // yet linked to anything. See app/routers/admin.py's own docstring.
  final String? linkedSummary;
  // Only populated for patient rows.
  final String? diagnosis;
}
