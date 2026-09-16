class Recording {
  const Recording({
    required this.id,
    required this.name,
    required this.fileName,
    required this.localPath,
    required this.durationMs,
    required this.createdAt,
    this.fileMissing = false,
  });

  final String id;
  final String name;
  final String fileName;
  final String localPath;
  final int durationMs;
  final DateTime createdAt;
  final bool fileMissing;

  bool get canPlay => !fileMissing;

  Recording copyWith({bool? fileMissing}) {
    return Recording(
      id: id,
      name: name,
      fileName: fileName,
      localPath: localPath,
      durationMs: durationMs,
      createdAt: createdAt,
      fileMissing: fileMissing ?? this.fileMissing,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'file_name': fileName,
      'local_path': localPath,
      'duration_ms': durationMs,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Recording.fromMap(
    Map<String, Object?> map, {
    bool fileMissing = false,
  }) {
    return Recording(
      id: map['id']! as String,
      name: map['name']! as String,
      fileName: map['file_name']! as String,
      localPath: map['local_path']! as String,
      durationMs: (map['duration_ms']! as num).toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at']! as num).toInt(),
      ),
      fileMissing: fileMissing,
    );
  }
}
