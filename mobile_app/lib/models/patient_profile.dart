/// Mirrors PatientOut (app/schemas/patient.py) — see context/api-contracts.md.
class PatientProfile {
  PatientProfile({
    required this.id,
    required this.mrNumber,
    required this.diagnosis,
    required this.age,
    required this.baselineStage,
    required this.dayCount,
    required this.assignedDoctorId,
    required this.userId,
    required this.attendantUserId,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.medicationInfo,
    required this.attendantName,
    required this.assignedDoctorName,
  });

  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
        id: json['id'] as int,
        mrNumber: json['mr_number'] as String?,
        diagnosis: json['diagnosis'] as String?,
        age: json['age'] as int?,
        baselineStage: json['baseline_stage'] as String,
        dayCount: json['day_count'] as int,
        assignedDoctorId: json['assigned_doctor_id'] as int?,
        userId: json['user_id'] as int?,
        attendantUserId: json['attendant_user_id'] as int?,
        emergencyContactName: json['emergency_contact_name'] as String?,
        emergencyContactPhone: json['emergency_contact_phone'] as String?,
        medicationInfo: json['medication_info'] as String?,
        attendantName: json['attendant_name'] as String?,
        assignedDoctorName: json['assigned_doctor_name'] as String?,
      );

  final int id;
  final String? mrNumber;
  final String? diagnosis;
  final int? age;
  final String baselineStage; // cold_start | learning | personalized
  final int dayCount;
  final int? assignedDoctorId;
  final int? userId;
  final int? attendantUserId;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? medicationInfo;
  final String? attendantName;
  final String? assignedDoctorName;

  /// Days-needed denominator for the baseline progress bar — matches the
  /// prototype's "18 of 14 needed entries" framing (day 15 = personalized).
  int get daysUntilPersonalized => (15 - dayCount).clamp(0, 15);

  String get baselineStageLabel {
    switch (baselineStage) {
      case 'personalized':
        return 'Personalised pattern model';
      case 'learning':
        return 'Learning your pattern';
      default:
        return 'Collecting your first ranges';
    }
  }

  /// List of "Name dose · time" strings — medication_info is stored as one
  /// semicolon-separated free-text field (see context/schema.md); split for
  /// display as individual chips, matching the prototype's Medicines row.
  List<String> get medicationList {
    final raw = medicationInfo;
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
