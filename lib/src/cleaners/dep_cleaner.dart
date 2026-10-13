import 'dart:io';

import '../backup/backup_manager.dart';
import '../backup/backup_manifest.dart';
import '../packages/package_dep_models.dart';
import '../utils.dart';

/// Result summary of a dependency cleaning operation.
class CleanDependenciesResult {
  /// Total count of unused and duplicate dependency declarations removed.
  final int removedCount;

  /// Number of `pubspec.yaml` files updated.
  final int updatedPubspecsCount;

  /// List of package names removed.
  final List<String> removedPackageNames;

  /// The backup manifest created before cleaning, or null if dry-run.
  final BackupManifest? backupManifest;

  /// Creates a new [CleanDependenciesResult].
  CleanDependenciesResult({
    required this.removedCount,
    required this.updatedPubspecsCount,
    required this.removedPackageNames,
    this.backupManifest,
  });
}

/// Surgical cleaner that removes unused and duplicate dependencies from targeted `pubspec.yaml` files.
class DependencyCleaner {
  /// The project or workspace root directory.
  final Directory workspaceRoot;

  /// The backup manager used for snapshotting files before modification.
  final BackupManager backupManager;

  /// Creates a new [DependencyCleaner].
  DependencyCleaner({
    Directory? workspaceRoot,
    BackupManager? backupManager,
  })  : workspaceRoot = workspaceRoot ?? findProjectOrWorkspaceRoot(),
        backupManager = backupManager ??
            BackupManager(workspaceRoot ?? findProjectOrWorkspaceRoot());

  /// Performs surgical dependency removal on targeted `pubspec.yaml` files.
  CleanDependenciesResult clean({
    required List<UnusedDependencyItem> issues,
    bool dryRun = false,
    bool createBackup = true,
    BackupManifest? sharedBackup,
  }) {
    if (issues.isEmpty) {
      return CleanDependenciesResult(
        removedCount: 0,
        updatedPubspecsCount: 0,
        removedPackageNames: [],
      );
    }

    final removedNames = issues.map((i) => i.packageName).toSet().toList();

    // Group issues by target pubspec file
    final pubspecGroups = <String, List<UnusedDependencyItem>>{};
    final fileMap = <String, File>{};

    for (final item in issues) {
      final canon = canonicalizePath(item.pubspecFile.path);
      pubspecGroups.putIfAbsent(canon, () => []).add(item);
      fileMap[canon] = item.pubspecFile;
    }

    if (dryRun) {
      return CleanDependenciesResult(
        removedCount: issues.length,
        updatedPubspecsCount: pubspecGroups.length,
        removedPackageNames: removedNames,
      );
    }

    // 1. Create or append backup snapshot of all pubspec.yaml files targeted for modification
    final filesToBackup = fileMap.values.where((f) => f.existsSync()).toList();
    BackupManifest? manifest;
    if (sharedBackup != null) {
      backupManager.appendToBackup(
        sharedBackup,
        filesToBackup,
      );
      manifest = sharedBackup;
    } else if (createBackup) {
      manifest = backupManager.createBackup(
        action: 'clean-packages',
        filesToBackup: filesToBackup,
      );
    }

    int updatedPubspecs = 0;
    int totalRemoved = 0;

    // 2. Surgically prune each pubspec.yaml
    for (final entry in pubspecGroups.entries) {
      final pubFile = fileMap[entry.key]!;
      final fileIssues = entry.value;

      if (!pubFile.existsSync()) continue;

      if (_prunePubspecDependencies(pubFile, fileIssues)) {
        updatedPubspecs++;
        totalRemoved += fileIssues.length;
      }
    }

    return CleanDependenciesResult(
      removedCount: totalRemoved,
      updatedPubspecsCount: updatedPubspecs,
      removedPackageNames: removedNames,
      backupManifest: manifest,
    );
  }

  /// Surgically removes targeted dependency entries from [pubFile].
  bool _prunePubspecDependencies(
      File pubFile, List<UnusedDependencyItem> issuesToRemove) {
    try {
      final lines = pubFile.readAsLinesSync();

      // Sort items by startLine descending so removing lines doesn't shift earlier line numbers
      final sortedItems = List<UnusedDependencyItem>.from(issuesToRemove)
        ..sort((a, b) => b.startLine.compareTo(a.startLine));

      final linesList = List<String>.from(lines);

      for (final item in sortedItems) {
        final startIdx = item.startLine - 1; // 0-based
        final endIdx = item.endLine - 1; // 0-based

        if (startIdx >= 0 && endIdx < linesList.length && startIdx <= endIdx) {
          // Verify that the line at startIdx indeed references the target package
          final targetLine = linesList[startIdx];
          final pkgRegex = RegExp('^\\s*${RegExp.escape(item.packageName)}:');

          if (pkgRegex.hasMatch(targetLine)) {
            // Remove the block of lines from startIdx to endIdx
            final countToRemove = endIdx - startIdx + 1;
            for (int r = 0; r < countToRemove; r++) {
              if (startIdx < linesList.length) {
                linesList.removeAt(startIdx);
              }
            }
          }
        }
      }

      // Write updated content back to the file
      pubFile.writeAsStringSync('${linesList.join('\n')}\n');
      return true;
    } catch (_) {
      return false;
    }
  }
}
