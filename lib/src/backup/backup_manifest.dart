import 'dart:convert';

/// Metadata entry representing a single file preserved in a backup snapshot.
class BackupFileEntry {
  /// The absolute system path of the original file.
  final String originalPath;

  /// The project-relative path of the original file.
  final String relativePath;

  /// The relative path of the archived copy inside the backup directory.
  final String backupRelativePath;

  /// Whether the file was originally deleted (true) or modified (false).
  final bool isDeleted;

  /// Creates a new [BackupFileEntry].
  BackupFileEntry({
    required this.originalPath,
    required this.relativePath,
    required this.backupRelativePath,
    this.isDeleted = false,
  });

  /// Serializes this entry into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'originalPath': originalPath,
        'relativePath': relativePath,
        'backupRelativePath': backupRelativePath,
        'isDeleted': isDeleted,
      };

  /// Deserializes a [BackupFileEntry] from a JSON map.
  factory BackupFileEntry.fromJson(Map<String, dynamic> json) {
    return BackupFileEntry(
      originalPath: json['originalPath'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      backupRelativePath: json['backupRelativePath'] as String? ?? '',
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }
}

/// Metadata describing a complete backup snapshot created before a code cleanup operation.
class BackupManifest {
  /// Sequential integer ID of the backup snapshot (e.g. 1, 2, 3...).
  final int id;

  /// ISO 8601 formatted timestamp when the backup was created.
  final String timestamp;

  /// Human-readable description of the cleanup action that triggered this backup.
  final String action;

  /// Directory name of the backup folder.
  final String backupDirName;

  /// List of files preserved in this backup.
  final List<BackupFileEntry> files;

  /// Creates a new [BackupManifest].
  BackupManifest({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.backupDirName,
    required this.files,
  });

  /// Formatted creation date string for user display.
  String get formattedDate {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp;
    }
  }

  /// Serializes this manifest into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'action': action,
        'backupDirName': backupDirName,
        'files': files.map((f) => f.toJson()).toList(),
      };

  /// Formats this manifest as an indented JSON string.
  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Deserializes a [BackupManifest] from a JSON map.
  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List<dynamic>? ?? [];
    final files = rawFiles
        .whereType<Map<String, dynamic>>()
        .map((f) => BackupFileEntry.fromJson(f))
        .toList();

    return BackupManifest(
      id: json['id'] as int? ?? 1,
      timestamp:
          json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      action: json['action'] as String? ?? 'Code cleanup',
      backupDirName: json['backupDirName'] as String? ?? '',
      files: files,
    );
  }
}
