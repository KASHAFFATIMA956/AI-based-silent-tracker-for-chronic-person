/// Mirrors MessageOut (app/schemas/message.py) — see context/api-contracts.md.
/// Added 2026-09-07 (direct-messaging pass).
class Message {
  Message({
    required this.id,
    required this.patientId,
    required this.senderUserId,
    required this.senderRole,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as int,
        patientId: json['patient_id'] as int,
        senderUserId: json['sender_user_id'] as int,
        senderRole: json['sender_role'] as String,
        senderName: json['sender_name'] as String?,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
      );

  final int id;
  final int patientId;
  final int senderUserId;
  final String senderRole; // patient | attendant | doctor
  final String? senderName;
  final String content;
  final DateTime createdAt;
  // Always null for now — no endpoint sets this yet, see
  // app/models/message.py. Kept on the model since the backend returns it.
  final DateTime? readAt;
}
