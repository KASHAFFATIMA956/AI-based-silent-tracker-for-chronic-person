/// Mirrors RiskResultOut / EntryOut (app/schemas/entry.py) — see
/// context/api-contracts.md. Used for both the POST /entries response and
/// each item of GET /entries/{patient_id}/timeline (same shape).
class RiskResult {
  RiskResult({
    required this.riskLevel,
    required this.riskTitle,
    required this.riskMessage,
    required this.reasoning,
    required this.source,
  });

  factory RiskResult.fromJson(Map<String, dynamic> json) => RiskResult(
        riskLevel: json['risk_level'] as String,
        riskTitle: json['risk_title'] as String?,
        riskMessage: json['risk_message'] as String?,
        reasoning: json['reasoning'] as String?,
        source: json['source'] as String,
      );

  final String riskLevel; // Green | Yellow | Orange | Red
  final String? riskTitle;
  final String? riskMessage;
  final String? reasoning;
  final String source; // rule | merged
}

class Entry {
  Entry({
    required this.id,
    required this.patientId,
    required this.entryType,
    required this.timestamp,
    required this.rawTranscript,
    required this.transcriptTranslation,
    required this.sleepValue,
    required this.energyValue,
    required this.moodValue,
    required this.appetiteValue,
    required this.mobilityValue,
    required this.weightValue,
    required this.medicineStatus,
    required this.symptomNames,
    required this.riskResult,
    this.hasAudio = false,
    this.acousticFeatures,
  });

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
        id: json['id'] as int,
        patientId: json['patient_id'] as int,
        entryType: json['entry_type'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        rawTranscript: json['raw_transcript'] as String?,
        transcriptTranslation: json['transcript_translation'] as String?,
        sleepValue: (json['sleep_value'] as num?)?.toDouble(),
        energyValue: (json['energy_value'] as num?)?.toDouble(),
        moodValue: (json['mood_value'] as num?)?.toDouble(),
        appetiteValue: (json['appetite_value'] as num?)?.toDouble(),
        mobilityValue: (json['mobility_value'] as num?)?.toDouble(),
        weightValue: (json['weight_value'] as num?)?.toDouble(),
        medicineStatus: json['medicine_status'] as String,
        symptomNames: (json['symptom_names'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        riskResult: json['risk_result'] == null
            ? null
            : RiskResult.fromJson(json['risk_result'] as Map<String, dynamic>),
        hasAudio: json['has_audio'] as bool? ?? false,
        acousticFeatures: json['acoustic_features'] as Map<String, dynamic>?,
      );

  final int id;
  final int patientId;
  final String entryType; // voice | quick
  final DateTime timestamp;
  final String? rawTranscript;
  final String? transcriptTranslation;
  final double? sleepValue;
  final double? energyValue;
  final double? moodValue;
  final double? appetiteValue;
  final double? mobilityValue;
  final double? weightValue;
  final String medicineStatus; // taken | missed
  final List<String> symptomNames;
  final RiskResult? riskResult;
  // Added 2026-08-25 (acoustic-analysis pass) — see
  // context/api-contracts.md POST /entries/{id}/audio.
  final bool hasAudio;
  final Map<String, dynamic>? acousticFeatures;
}

/// Mirrors SymptomChecklistItem (app/schemas/patient.py).
class SymptomOption {
  SymptomOption({required this.id, required this.symptomName});

  factory SymptomOption.fromJson(Map<String, dynamic> json) => SymptomOption(
        id: json['id'] as int,
        symptomName: json['symptom_name'] as String,
      );

  final int id;
  final String symptomName;
}
