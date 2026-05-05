import 'chat_message_model.dart';

class ChatSessionModel {
  final String? id;
  final String userId;
  final DateTime startedAt;
  final DateTime updatedAt;
  final List<ChatMessageModel> messages;

  ChatSessionModel({
    this.id,
    required this.userId,
    required this.startedAt,
    required this.updatedAt,
    required this.messages,
  });

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? [];
    return ChatSessionModel(
      id: json['_id']?.toString(),
      userId: json['userId'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      messages: rawMessages
          .map((m) => ChatMessageModel.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
