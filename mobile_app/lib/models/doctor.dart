/// Mirrors DoctorPatientRosterItem / AlertOut / DoctorNoteOut
/// (app/schemas/doctor.py) — see context/api-contracts.md.
class DoctorPatientRosterItem {
  DoctorPatientRosterItem({
    required this.patientId,
    required this.name,
    required this.mrNumber,
    required this.age,
    required this.diagnosis,
    required this.dayCount,
    required this.baselineStage,
    required this.latestRiskLevel,
    required this.latestReasoning,
    required this.lastEntryTimestamp,
  });

  factory DoctorPatientRosterItem.fromJson(Map<String, dynamic> json) => DoctorPatientRosterItem(
        patientId: json['patient_id'] as int,
        name: json['name'] as String,
        mrNumber: json['mr_number'] as String?,
        age: json['age'] as int?,
        diagnosis: json['diagnosis'] as String?,
        dayCount: json['day_count'] as int,
        baselineStage: json['baseline_stage'] as String,
        latestRiskLevel: json['latest_risk_level'] as String?,
        latestReasoning: json['latest_reasoning'] as String?,
        lastEntryTimestamp: json['last_entry_timestamp'] == null
            ? null
            : DateTime.parse(json['last_entry_timestamp'] as String),
      );

  final int patientId;
  final String name;
  final String? mrNumber;
  final int? age;
  final String? diagnosis;
  final int dayCount;
  final String baselineStage; // cold_start | learning | personalized
  // Null when the patient has no entries yet (roster sorts these last —
  // see context/api-contracts.md).
  final String? latestRiskLevel; // Green | Yellow | Orange | Red
  final String? latestReasoning;
  final DateTime? lastEntryTimestamp;
}

/// Mirrors AlertOut. Same shape for both GET /doctors/{id}/alerts rows and
/// the POST /alerts/{id}/review response.
class AlertItem {
  AlertItem({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.entryId,
    required this.riskLevel,
    required this.alertText,
    required this.sourceRule,
    required this.reviewed,
    required this.createdAt,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
        id: json['id'] as int,
        patientId: json['patient_id'] as int,
        patientName: json['patient_name'] as String,
        entryId: json['entry_id'] as int?,
        riskLevel: json['risk_level'] as String,
        alertText: json['alert_text'] as String,
        sourceRule: json['source_rule'] as String?,
        reviewed: json['reviewed'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final int patientId;
  final String patientName;
  final int? entryId;
  final String riskLevel; // Green | Yellow | Orange | Red
  final String alertText;
  final String? sourceRule;
  final bool reviewed;
  final DateTime createdAt;
}

/// Mirrors DoctorNoteOut.
class DoctorNote {
  DoctorNote({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.noteText,
    required this.createdAt,
  });

  factory DoctorNote.fromJson(Map<String, dynamic> json) => DoctorNote(
        id: json['id'] as int,
        patientId: json['patient_id'] as int,
        doctorId: json['doctor_id'] as int,
        doctorName: json['doctor_name'] as String,
        noteText: json['note_text'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final int patientId;
  final int doctorId;
  final String doctorName;
  final String noteText;
  final DateTime createdAt;
}
