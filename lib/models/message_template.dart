// models/message_template.dart
class MessageTemplate {
  final int? id;
  final String title;
  final String message;
  final String category;
  final DateTime createdAt;
  final int usageCount;
  final bool isDefault;

  MessageTemplate({
    this.id,
    required this.title,
    required this.message,
    this.category = 'general',
    DateTime? createdAt,
    this.usageCount = 0,
    this.isDefault = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'category': category,
      'created_at': createdAt.millisecondsSinceEpoch,
      'usage_count': usageCount,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory MessageTemplate.fromMap(Map<String, dynamic> map) {
    return MessageTemplate(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      category: map['category'] as String? ?? 'general',
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
      usageCount: map['usage_count'] as int? ?? 0,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
    );
  }
}
