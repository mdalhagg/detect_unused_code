import 'dart:convert';
import 'dart:io';

import '../utils.dart';
import 'backup_manifest.dart';

/// Result details following a backup restoration attempt.
class RestoreResult {
  /// Whether the restoration completed without error.
  final bool success;

  /// Human-readable message describing the outcome.
  final String message;

  /// The list of file paths that were restored.
  final List<String> restoredFiles;

  /// Creates a new [RestoreResult].
  RestoreResult({
    required this.success,
    required this.message,
    this.restoredFiles = const [],
  });
}

/// Manages snapshot creation, archiving, and restoration for safe code cleanup operations.
class BackupManager {
  /// The root directory of the project.
  final Directory projectRoot;

  /// Creates a new [BackupManager] scoped to [projectRoot].
  BackupManager(this.projectRoot);

  /// The directory where backups are stored inside the project.
  Directory get backupBaseDir =>
      Directory('${projectRoot.path}/.detect_unused/backups');

  /// Ensures that `.detect_unused` is added to the project's `.gitignore` file.
  void ensureGitIgnore() {
    try {
      final gitIgnoreFile = File('${projectRoot.path}/.gitignore');
      if (gitIgnoreFile.existsSync()) {
        final content = gitIgnoreFile.readAsStringSync();
        if (!content.contains('.detect_unused')) {
          final prefix = content.endsWith('\n') ? '' : '\n';
          gitIgnoreFile.writeAsStringSync(
            '$prefix\n# detect_unused_code backups\n.detect_unused/\n',
            mode: FileMode.append,
          );
        }
      }
    } catch (_) {}
  }

  /// Creates a complete snapshot of all files targeted for cleanup.
  BackupManifest createBackup({
    required String action,
    required Iterable<File> filesToBackup,
    Iterable<String>? filesMarkedForDeletion,
  }) {
    ensureGitIgnore();

    final base = backupBaseDir;
    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }

    final existing = listBackups();
    final nextId = existing.isEmpty ? 1 : (existing.first.id + 1);

    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
    final dirName = 'backup_${nextId}_$stamp';
    final backupDir = Directory('${base.path}/$dirName');
    backupDir.createSync(recursive: true);

    final entries = <BackupFileEntry>[];
    final filesSet = <String>{};

    for (final file in filesToBackup) {
      if (!file.existsSync()) {
        continue;
      }
      final canon = canonicalizePath(file.path);
      if (filesSet.contains(canon)) {
        continue;
      }
      filesSet.add(canon);

      final rel = getRelativePath(file.path, projectRoot.path);
      final destFile = File('${backupDir.path}/files/$rel');
      destFile.parent.createSync(recursive: true);
      file.copySync(destFile.path);

      entries.add(BackupFileEntry(
        originalPath: file.path,
        relativePath: rel,
        backupRelativePath: 'files/$rel',
        isDeleted: false,
      ));
    }

    if (filesMarkedForDeletion != null) {
      for (final path in filesMarkedForDeletion) {
        final canon = canonicalizePath(path);
        if (filesSet.contains(canon)) {
          // Update entry to mark as deleted
          final idx = entries
              .indexWhere((e) => canonicalizePath(e.originalPath) == canon);
          if (idx != -1) {
            final old = entries[idx];
            entries[idx] = BackupFileEntry(
              originalPath: old.originalPath,
              relativePath: old.relativePath,
              backupRelativePath: old.backupRelativePath,
              isDeleted: true,
            );
          }
        }
      }
    }

    final manifest = BackupManifest(
      id: nextId,
      timestamp: now.toIso8601String(),
      action: action,
      backupDirName: dirName,
      files: entries,
    );

    final manifestFile = File('${backupDir.path}/manifest.json');
    manifestFile.writeAsStringSync(manifest.toPrettyJson());

    return manifest;
  }

  /// Adds additional files to an existing backup manifest snapshot before they are modified.
  void appendToBackup(
    BackupManifest manifest,
    Iterable<File> additionalFiles,
  ) {
    final backupDir =
        Directory('${backupBaseDir.path}/${manifest.backupDirName}');
    if (!backupDir.existsSync()) {
      return;
    }

    final existingSet =
        manifest.files.map((e) => canonicalizePath(e.originalPath)).toSet();

    for (final file in additionalFiles) {
      if (!file.existsSync()) {
        continue;
      }
      final canon = canonicalizePath(file.path);
      if (existingSet.contains(canon)) {
        continue;
      }
      existingSet.add(canon);

      final rel = getRelativePath(file.path, projectRoot.path);
      final destFile = File('${backupDir.path}/files/$rel');
      destFile.parent.createSync(recursive: true);
      file.copySync(destFile.path);

      manifest.files.add(BackupFileEntry(
        originalPath: file.path,
        relativePath: rel,
        backupRelativePath: 'files/$rel',
        isDeleted: false,
      ));
    }

    final manifestFile = File('${backupDir.path}/manifest.json');
    manifestFile.writeAsStringSync(manifest.toPrettyJson());
  }

  /// Lists all available backup snapshots sorted by ID in descending order (newest first).
  List<BackupManifest> listBackups() {
    final base = backupBaseDir;
    if (!base.existsSync()) {
      return [];
    }

    final list = <BackupManifest>[];
    try {
      final dirs = base.listSync().whereType<Directory>();
      for (final dir in dirs) {
        final mf = File('${dir.path}/manifest.json');
        if (mf.existsSync()) {
          try {
            final content = mf.readAsStringSync();
            final json = jsonDecode(content) as Map<String, dynamic>;
            list.add(BackupManifest.fromJson(json));
          } catch (_) {}
        }
      }
    } catch (_) {}

    list.sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  /// Retrieves a specific backup snapshot by its integer [id].
  BackupManifest? getBackup(int id) {
    final all = listBackups();
    for (final b in all) {
      if (b.id == id) {
        return b;
      }
    }
    return null;
  }

  /// Retrieves the most recently created backup snapshot, if one exists.
  BackupManifest? getLatestBackup() {
    final all = listBackups();
    return all.isEmpty ? null : all.first;
  }

  /// Restores all files in backup [id] back to their original state.
  RestoreResult restoreBackup(int id) {
    final manifest = getBackup(id);
    if (manifest == null) {
      return RestoreResult(
        success: false,
        message: 'Backup #$id was not found in ${backupBaseDir.path}',
      );
    }

    final backupDir =
        Directory('${backupBaseDir.path}/${manifest.backupDirName}');
    if (!backupDir.existsSync()) {
      return RestoreResult(
        success: false,
        message: 'Backup directory "${backupDir.path}" does not exist.',
      );
    }

    final restored = <String>[];
    try {
      for (final entry in manifest.files) {
        final archivedFile =
            File('${backupDir.path}/${entry.backupRelativePath}');
        final targetFile = File(entry.originalPath);

        if (archivedFile.existsSync()) {
          targetFile.parent.createSync(recursive: true);
          archivedFile.copySync(targetFile.path);
          restored.add(entry.relativePath);
        }
      }

      return RestoreResult(
        success: true,
        message:
            'Backup #$id restored successfully (${restored.length} files restored).',
        restoredFiles: restored,
      );
    } catch (e) {
      return RestoreResult(
        success: false,
        message: 'Restoration failed midway: $e',
        restoredFiles: restored,
      );
    }
  }

  /// Restores the most recent backup snapshot.
  RestoreResult restoreLatest() {
    final latest = getLatestBackup();
    if (latest == null) {
      return RestoreResult(
        success: false,
        message: 'No backups found to restore in ${backupBaseDir.path}.',
      );
    }
    return restoreBackup(latest.id);
  }
}
