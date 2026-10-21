import 'package:uuid/uuid.dart';

/// A user-defined list type. Deleted records remain available for sync.
class ListGroup {
  final String id;
  final String name;
  final int sortOrder;
  final String workspaceId;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  ListGroup({
    String? id,
    required String name,
    this.sortOrder = 0,
    this.workspaceId = 'private',
    this.isDeleted = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       name = name.trim(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  factory ListGroup.fromJson(Map<String, dynamic> json) => ListGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    sortOrder: (json['sortOrder'] as num).toInt(),
    workspaceId: json['workspaceId'] as String? ?? 'private',
    isDeleted: json['isDeleted'] == true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sortOrder': sortOrder,
    'workspaceId': workspaceId,
    'isDeleted': isDeleted,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  ListGroup copyWith({
    String? id,
    String? name,
    int? sortOrder,
    String? workspaceId,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ListGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    workspaceId: workspaceId ?? this.workspaceId,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
