import 'dart:io';

import '../assets/asset_auditor.dart';
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
    bool createBackup = true,
    BackupManifest? sharedBackup,
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

    // 1. Group unused assets by their owning package pubspec file
    final pubspecModifications = <File, List<UnusedAssetItem>>{};
    final packageRoots = <File, Directory>{};
    for (final item in unusedAssets) {
      final pubFile = item.ownerPackage.pubspecFile;
      pubspecModifications.putIfAbsent(pubFile, () => []).add(item);
      packageRoots[pubFile] = item.ownerPackage.packageRootDir;
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

    // 3. Create or append Backup Snapshot of all files targeted for deletion AND all pubspec.yaml files targeted for modification
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

    BackupManifest? manifest;
    if (sharedBackup != null) {
      backupManager.appendToBackup(
        sharedBackup,
        filesToBackup,
        filesMarkedForDeletion: filesMarkedForDeletion,
      );
      manifest = sharedBackup;
    } else if (createBackup) {
      manifest = backupManager.createBackup(
        action: 'clean-assets',
        filesToBackup: filesToBackup,
        filesMarkedForDeletion: filesMarkedForDeletion,
      );
    }

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

    // 5. Surgically remove explicit entries (both assets and font assets) from their respective pubspec.yaml
    int updatedPubspecs = 0;
    for (final entry in pubspecModifications.entries) {
      final pubFile = entry.key;
      final itemsToRemove = entry.value;
      final pkgRoot = packageRoots[pubFile] ?? workspaceRoot;

      if (_prunePubspecAssetsAndFonts(pubFile, pkgRoot, itemsToRemove)) {
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

  /// Checks if a directory contains no supported media or font files.
  bool _isDirEmptyOfAssets(Directory dir) {
    if (!dir.existsSync()) return true;
    try {
      final list = dir.listSync(recursive: true, followLinks: false);
      for (final entity in list) {
        if (entity is File) {
          final ext = entity.uri.pathSegments.safeLast
                  ?.split('.')
                  .safeLast
                  ?.toLowerCase() ??
              '';
          if (AssetAuditor.supportedExtensions.contains(ext)) {
            return false;
          }
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Surgically removes unused asset and font entries from [pubFile].
  bool _prunePubspecAssetsAndFonts(
    File pubFile,
    Directory packageRootDir,
    List<UnusedAssetItem> unusedItems,
  ) {
    if (!pubFile.existsSync()) return false;

    try {
      final lines = pubFile.readAsLinesSync();
      final targetPaths = <String>{};
      for (final item in unusedItems) {
        final rel = item.packageRelativePath.replaceAll(r'\', '/');
        targetPaths.add(rel);
        targetPaths.add(rel.replaceFirst(RegExp(r'^\.?/'), ''));
        final fromPkgRoot =
            getRelativePath(item.absolutePath, packageRootDir.path)
                .replaceAll(r'\', '/');
        targetPaths.add(fromPkgRoot);
        targetPaths.add(fromPkgRoot.replaceFirst(RegExp(r'^\.?/'), ''));
      }

      bool modified = false;
      final newLines = <String>[];
      int i = 0;
      bool inFlutter = false;
      int flutterIndent = 0;

      while (i < lines.length) {
        final line = lines[i];
        final trimmed = line.trim();
        final indent = line.indexOf(line.trimLeft());

        // Track top-level flutter: section
        if (indent == 0 && trimmed.startsWith('flutter:')) {
          inFlutter = true;
          flutterIndent = indent;
          newLines.add(line);
          i++;
          continue;
        } else if (indent <= flutterIndent &&
            trimmed.isNotEmpty &&
            !trimmed.startsWith('#') &&
            inFlutter) {
          inFlutter = false;
        }

        if (!inFlutter) {
          newLines.add(line);
          i++;
          continue;
        }

        // 1. Process assets: section
        if (trimmed.startsWith('assets:')) {
          final assetsHeaderLine = line;
          final assetsIndent = indent;
          i++;

          final rawAssetLines = <String>[];
          while (i < lines.length) {
            final nextLine = lines[i];
            final nextTrimmed = nextLine.trim();
            final nextIndent = nextLine.indexOf(nextLine.trimLeft());

            if (nextTrimmed.isEmpty) {
              rawAssetLines.add(nextLine);
              i++;
              continue;
            }

            if (nextIndent <= assetsIndent &&
                !nextTrimmed.startsWith('-') &&
                !nextTrimmed.startsWith('#')) {
              break;
            }

            rawAssetLines.add(nextLine);
            i++;
          }

          final keptAssetLines = <String>[];
          for (final aLine in rawAssetLines) {
            final aTrimmed = aLine.trim();
            if (aTrimmed.isEmpty || aTrimmed.startsWith('#')) {
              keptAssetLines.add(aLine);
              continue;
            }

            if (aTrimmed.startsWith('-')) {
              var rawEntry = aTrimmed.substring(1).trim();
              if (rawEntry.contains('#')) {
                rawEntry = rawEntry.substring(0, rawEntry.indexOf('#')).trim();
              }
              rawEntry = rawEntry
                  .replaceAll(RegExp(r'''^["']+|["']+$'''), '')
                  .trim()
                  .replaceAll(r'\', '/');
              final cleanEntry = rawEntry.replaceFirst(RegExp(r'^\.?/'), '');

              // Check if entry matches an unused asset
              if (targetPaths.contains(rawEntry) ||
                  targetPaths.contains(cleanEntry)) {
                modified = true;
                continue;
              }

              // Check if directory pattern that is now empty or missing
              final isDirPattern = rawEntry.endsWith('/') ||
                  FileSystemEntity.isDirectorySync(
                      '${packageRootDir.path}/$cleanEntry');
              if (isDirPattern) {
                final dir = Directory('${packageRootDir.path}/$cleanEntry');
                if (!dir.existsSync() || _isDirEmptyOfAssets(dir)) {
                  modified = true;
                  continue;
                }
              }

              keptAssetLines.add(aLine);
            } else {
              keptAssetLines.add(aLine);
            }
          }

          final hasItems =
              keptAssetLines.any((l) => l.trim().startsWith('-'));
          if (hasItems) {
            newLines.add(assetsHeaderLine);
            newLines.addAll(keptAssetLines);
          } else {
            // Drop entire assets: section
            modified = true;
          }
          continue;
        }

        // 2. Process fonts: section
        if (trimmed.startsWith('fonts:')) {
          final fontsHeaderLine = line;
          final fontsIndent = indent;
          i++;

          final rawFontLines = <String>[];
          while (i < lines.length) {
            final nextLine = lines[i];
            final nextTrimmed = nextLine.trim();
            final nextIndent = nextLine.indexOf(nextLine.trimLeft());

            if (nextTrimmed.isEmpty) {
              rawFontLines.add(nextLine);
              i++;
              continue;
            }

            if (nextIndent <= fontsIndent &&
                !nextTrimmed.startsWith('-') &&
                !nextTrimmed.startsWith('#')) {
              break;
            }

            rawFontLines.add(nextLine);
            i++;
          }

          final families = _parseFontFamilies(rawFontLines);
          final keptFamilyLines = <String>[];

          for (final fam in families) {
            final keptAssets = fam.fontAssets.where((asset) {
              final clean =
                  asset.normalizedPath.replaceFirst(RegExp(r'^\.?/'), '');
              final isUnused = targetPaths.contains(asset.normalizedPath) ||
                  targetPaths.contains(clean);
              if (isUnused) {
                modified = true;
                return false;
              }
              return true;
            }).toList();

            if (keptAssets.isNotEmpty) {
              keptFamilyLines.addAll(fam.headerLines);
              for (final a in keptAssets) {
                keptFamilyLines.addAll(a.lines);
              }
              keptFamilyLines.addAll(fam.trailingLines);
            } else {
              // Entire family pruned
              modified = true;
            }
          }

          if (keptFamilyLines.isNotEmpty) {
            newLines.add(fontsHeaderLine);
            newLines.addAll(keptFamilyLines);
          } else {
            // Entire fonts: section pruned
            modified = true;
          }
          continue;
        }

        newLines.add(line);
        i++;
      }

      if (modified) {
        // Clean up duplicate consecutive blank lines
        final cleanedLines = <String>[];
        bool prevBlank = false;
        for (final l in newLines) {
          final isBlank = l.trim().isEmpty;
          if (isBlank && prevBlank) continue;
          cleanedLines.add(l);
          prevBlank = isBlank;
        }

        pubFile.writeAsStringSync('${cleanedLines.join('\n')}\n');
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Parses raw lines under `fonts:` into structured font families.
  List<_FontFamilySection> _parseFontFamilies(List<String> fontLines) {
    final families = <_FontFamilySection>[];
    List<String>? currentHeader;
    List<_FontAssetEntry> currentAssets = [];
    _FontAssetEntry? currentAsset;
    List<String> currentTrailing = [];

    void commitCurrentAsset() {
      if (currentAsset != null) {
        currentAssets.add(currentAsset!);
        currentAsset = null;
      }
    }

    void commitCurrentFamily() {
      commitCurrentAsset();
      if (currentHeader != null) {
        families.add(_FontFamilySection(
          headerLines: currentHeader!,
          fontAssets: currentAssets,
          trailingLines: currentTrailing,
        ));
        currentHeader = null;
        currentAssets = [];
        currentTrailing = [];
      }
    }

    for (final line in fontLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentAsset != null) {
          currentAsset!.lines.add(line);
        } else if (currentHeader != null && currentAssets.isEmpty) {
          currentHeader!.add(line);
        } else {
          currentTrailing.add(line);
        }
        continue;
      }

      final isNewFamily = trimmed.startsWith('- family:') ||
          (trimmed.startsWith('family:') && currentHeader == null);
      final isNewAsset = trimmed.startsWith('- asset:') ||
          (trimmed.startsWith('asset:') && currentHeader != null);

      if (isNewFamily) {
        commitCurrentFamily();
        currentHeader = [line];
      } else if (isNewAsset) {
        commitCurrentAsset();
        final m = RegExp(r'^-?\s*asset:\s*(.*)').firstMatch(trimmed);
        var fontPath = m != null ? m.group(1)!.trim() : '';
        if (fontPath.contains('#')) {
          fontPath = fontPath.substring(0, fontPath.indexOf('#')).trim();
        }
        fontPath = fontPath
            .replaceAll(RegExp(r'''^["']+|["']+$'''), '')
            .trim()
            .replaceAll(r'\', '/');
        currentAsset = _FontAssetEntry(normalizedPath: fontPath, lines: [line]);
      } else if (currentAsset != null &&
          (trimmed.startsWith('weight:') ||
              trimmed.startsWith('style:') ||
              trimmed.startsWith('#'))) {
        currentAsset!.lines.add(line);
      } else if (currentHeader != null &&
          currentAssets.isEmpty &&
          currentAsset == null) {
        currentHeader!.add(line);
      } else if (currentAsset != null) {
        currentAsset!.lines.add(line);
      } else if (currentHeader != null) {
        currentTrailing.add(line);
      }
    }

    commitCurrentFamily();
    return families;
  }
}

class _FontAssetEntry {
  final String normalizedPath;
  final List<String> lines;

  _FontAssetEntry({
    required this.normalizedPath,
    required this.lines,
  });
}

class _FontFamilySection {
  final List<String> headerLines;
  final List<_FontAssetEntry> fontAssets;
  final List<String> trailingLines;

  _FontFamilySection({
    required this.headerLines,
    required this.fontAssets,
    this.trailingLines = const [],
  });
}
