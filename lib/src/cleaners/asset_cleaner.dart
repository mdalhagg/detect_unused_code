import 'dart:io';

import '../assets/asset_models.dart';
import '../backup/backup_manager.dart';
import '../backup/backup_manifest.dart';
import '../utils.dart';

/// Result summary of an asset cleaning operation.
class CleanAssetsResult {
  /// Number of unused asset files successfully deleted from disk.
  final int deletedFilesCount;

  /// Total number of bytes freed.
  final int totalBytesFreed;

  /// Formatted string of freed storage (e.g. `2.50 MB`).
  final String formattedBytesFreed;

  /// Number of `pubspec.yaml` files updated.
  final int updatedPubspecsCount;

  /// The backup manifest created before cleaning, or null if dry-run.
  final BackupManifest? backupManifest;

  /// Creates a new [CleanAssetsResult].
  CleanAssetsResult({
    required this.deletedFilesCount,
    required this.totalBytesFreed,
    required this.formattedBytesFreed,
    required this.updatedPubspecsCount,
    this.backupManifest,
  });
}

/// Surgical cleaner for deleting unused assets and updating corresponding `pubspec.yaml` files.
class AssetCleaner {
  /// The project/workspace root directory.
  final Directory workspaceRoot;

  /// The backup manager used for snapshotting files before deletion.
  final BackupManager backupManager;

  /// Creates a new [AssetCleaner].
  AssetCleaner({
    Directory? workspaceRoot,
    BackupManager? backupManager,
  })  : workspaceRoot = workspaceRoot ?? findProjectOrWorkspaceRoot(),
        backupManager = backupManager ??
            BackupManager(workspaceRoot ?? findProjectOrWorkspaceRoot());

  /// Performs the asset cleanup across disk and pubspecs.
  CleanAssetsResult clean({
    required List<UnusedAssetItem> unusedAssets,
    bool dryRun = false,
  }) {
    if (unusedAssets.isEmpty) {
      return CleanAssetsResult(
        deletedFilesCount: 0,
        totalBytesFreed: 0,
        formattedBytesFreed: '0 B',
        updatedPubspecsCount: 0,
      );
    }

    int deletedCount = 0;
    int freedBytes = 0;

    // 1. Group explicit assets by their owning pubspec file
    final pubspecModifications = <File, List<String>>{};
    for (final item in unusedAssets) {
      if (item.isExplicitInPubspec) {
        final pubFile = item.ownerPackage.pubspecFile;
        pubspecModifications
            .putIfAbsent(pubFile, () => [])
            .add(item.packageRelativePath);
      }
    }

    // 2. Dry run preview
    if (dryRun) {
      for (final item in unusedAssets) {
        freedBytes += item.sizeInBytes;
        deletedCount++;
      }
      return CleanAssetsResult(
        deletedFilesCount: deletedCount,
        totalBytesFreed: freedBytes,
        formattedBytesFreed: formatByteSize(freedBytes),
        updatedPubspecsCount: pubspecModifications.length,
      );
    }

    // 3. Create Backup Snapshot of all files targeted for deletion AND all pubspec.yaml files targeted for modification
    final filesToBackup = <File>[];
    final filesMarkedForDeletion = <String>[];

    for (final item in unusedAssets) {
      final f = File(item.absolutePath);
      if (f.existsSync()) {
        filesToBackup.add(f);
        filesMarkedForDeletion.add(f.path);
      }
    }

    for (final pubFile in pubspecModifications.keys) {
      if (pubFile.existsSync()) {
        filesToBackup.add(pubFile);
      }
    }

    final manifest = backupManager.createBackup(
      action: 'clean-assets',
      filesToBackup: filesToBackup,
      filesMarkedForDeletion: filesMarkedForDeletion,
    );

    // 4. Delete physical files from disk & prune empty directories
    for (final item in unusedAssets) {
      try {
        final f = File(item.absolutePath);
        if (f.existsSync()) {
          final size = f.lengthSync();
          f.deleteSync();
          deletedCount++;
          freedBytes += size;

          // Recursively clean empty parent directories up to package root
          _pruneEmptyParentDirectories(
              f.parent, item.ownerPackage.packageRootDir);
        }
      } catch (_) {}
    }

    // 5. Surgically remove explicit entries from their respective pubspec.yaml
    int updatedPubspecs = 0;
    for (final entry in pubspecModifications.entries) {
      final pubFile = entry.key;
      final assetsToRemove = entry.value;

      if (_prunePubspecAssetLines(pubFile, assetsToRemove)) {
        updatedPubspecs++;
      }
    }

    return CleanAssetsResult(
      deletedFilesCount: deletedCount,
      totalBytesFreed: freedBytes,
      formattedBytesFreed: formatByteSize(freedBytes),
      updatedPubspecsCount: updatedPubspecs,
      backupManifest: manifest,
    );
  }

  /// Prunes empty directories starting from [startDir] up to, but not including, [stopAtDir].
  void _pruneEmptyParentDirectories(Directory startDir, Directory stopAtDir) {
    var cur = startDir;
    final canonStop = canonicalizePath(stopAtDir.path);

    while (cur.existsSync()) {
      final canonCur = canonicalizePath(cur.path);
      if (canonCur == canonStop || !canonCur.startsWith(canonStop)) {
        break;
      }

      try {
        final remaining = cur.listSync();
        if (remaining.isEmpty) {
          final parent = cur.parent;
          cur.deleteSync();
          cur = parent;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
  }

  /// Surgically removes explicit lines referencing [assetsToRemove] from [pubFile].
  bool _prunePubspecAssetLines(File pubFile, List<String> assetsToRemove) {
    if (!pubFile.existsSync()) return false;

    try {
      final lines = pubFile.readAsLinesSync();
      final targets =
          assetsToRemove.map((a) => a.replaceAll(r'\', '/')).toSet();
      final newLines = <String>[];
      bool modified = false;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();

        if (trimmed.startsWith('-')) {
          var entry = trimmed.substring(1).trim();
          if (entry.contains('#')) {
            entry = entry.substring(0, entry.indexOf('#')).trim();
          }
          entry = entry
              .replaceAll(RegExp(r'''^["']+|["']+$'''), '')
              .trim()
              .replaceAll(r'\', '/');

          if (targets.contains(entry)) {
            // Drop this line
            modified = true;
            continue;
          }
        }

        newLines.add(line);
      }

      if (modified) {
        pubFile.writeAsStringSync('${newLines.join('\n')}\n');
        return true;
      }
    } catch (_) {}

    return false;
  }
}
