class BatchModel {
  final String id;
  final String userId;
  final String name;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime? closedAt;
  final int totalDetections;

  BatchModel({
    required this.id,
    required this.userId,
    required this.name,
    this.notes,
    required this.status,
    required this.createdAt,
    this.closedAt,
    required this.totalDetections,
  });

  bool get isActive => status == 'active';

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[createdAt.month - 1]} ${createdAt.day}';
  }

  factory BatchModel.fromJson(Map<String, dynamic> json) {
    return BatchModel(
      id: json['_id']?.toString() ?? '',
      userId: json['userId'] as String,
      name: json['name'] as String,
      notes: json['notes'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      closedAt: json['closedAt'] != null
          ? DateTime.parse(json['closedAt'] as String)
          : null,
      totalDetections: (json['totalDetections'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'notes': notes,
      };
}
