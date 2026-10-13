import 'dart:io';

import '../utils.dart';
import 'asset_models.dart';

/// Scanner that flexibly discovers and parses all `pubspec.yaml` files across any workspace layout.
class PubspecScanner {
  /// Recursively walks [root] and finds all `pubspec.yaml` files in the workspace,
  /// skipping standard ignored directories (.git, .dart_tool, build, .detect_unused, etc.).
  static List<File> discoverPubspecFiles(Directory root) {
    final results = <File>[];
    if (!root.existsSync()) return results;

    void scanDir(Directory current) {
      try {
        final entities = current.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is Directory) {
            final dirName =
                entity.uri.pathSegments.where((s) => s.isNotEmpty).safeLast ??
                    '';
            if (ignoredDirNames.contains(dirName) || dirName.startsWith('.')) {
              continue;
            }
            scanDir(entity);
          } else if (entity is File) {
            final fileName = entity.uri.pathSegments.safeLast ?? '';
            if (fileName.toLowerCase() == 'pubspec.yaml') {
              results.add(entity);
            }
          }
        }
      } catch (_) {
        // Defensive: ignore unreadable directories or permission errors
      }
    }

    scanDir(root);

    // Sort so that deeper packages appear after root packages
    results.sort((a, b) => a.path.length.compareTo(b.path.length));
    return results;
  }

  /// Parses a discovered `pubspec.yaml` into a [PackageDescriptor].
  static PackageDescriptor parsePubspec(File file) {
    final parentDir = file.parent;
    String name =
        parentDir.uri.pathSegments.where((s) => s.isNotEmpty).safeLast ??
            'unknown_package';
    final declaredAssets = <String>[];
    final declaredFonts = <String, List<String>>{};

    try {
      final lines = file.readAsLinesSync();
      bool inFlutter = false;
      bool inAssets = false;
      bool inFonts = false;
      String? currentFontFamily;

      final nameRegex = RegExp(r'^\s*name:\s*([a-zA-Z0-9_-]+)');

      for (int i = 0; i < lines.length; i++) {
        final rawLine = lines[i];
        final trimmed = rawLine.trim();

        // 1. Package Name
        if (trimmed.startsWith('name:')) {
          final m = nameRegex.firstMatch(trimmed);
          if (m != null && m.group(1) != null) {
            name = m.group(1)!;
          }
          continue;
        }

        // Ignore empty lines and comment-only lines
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }

        // Determine indent
        final indent = rawLine.indexOf(rawLine.trimLeft());

        // Top-level sections (indent == 0)
        if (indent == 0) {
          if (trimmed.startsWith('flutter:')) {
            inFlutter = true;
          } else {
            inFlutter = false;
          }
          inAssets = false;
          inFonts = false;
          currentFontFamily = null;
          continue;
        }

        if (!inFlutter) continue;

        // Inside flutter: section
        if (trimmed.startsWith('assets:')) {
          inAssets = true;
          inFonts = false;
          currentFontFamily = null;
          continue;
        } else if (trimmed.startsWith('fonts:')) {
          if (indent <= 2) {
            inFonts = true;
            inAssets = false;
            currentFontFamily = null;
          }
          continue;
        } else if (indent <= 2 && !trimmed.startsWith('-')) {
          // Exited assets/fonts sub-section
          inAssets = false;
          inFonts = false;
          currentFontFamily = null;
        }

        // Parsing declared assets
        if (inAssets) {
          if (trimmed.startsWith('-')) {
            var assetPath = trimmed.substring(1).trim();
            // Strip any trailing comment
            if (assetPath.contains('#')) {
              assetPath = assetPath.substring(0, assetPath.indexOf('#')).trim();
            }
            // Strip quotes
            assetPath =
                assetPath.replaceAll(RegExp(r'''^["']+|["']+$'''), '').trim();
            if (assetPath.isNotEmpty) {
              declaredAssets.add(assetPath.replaceAll(r'\', '/'));
            }
          }
        }

        // Parsing declared fonts
        if (inFonts) {
          if (trimmed.startsWith('- family:')) {
            var fam = trimmed.substring('- family:'.length).trim();
            fam = fam.replaceAll(RegExp(r'''^["']+|["']+$'''), '').trim();
            currentFontFamily = fam;
            if (!declaredFonts.containsKey(fam)) {
              declaredFonts[fam] = [];
            }
          } else if (trimmed.startsWith('family:')) {
            var fam = trimmed.substring('family:'.length).trim();
            fam = fam.replaceAll(RegExp(r'''^["']+|["']+$'''), '').trim();
            currentFontFamily = fam;
            if (!declaredFonts.containsKey(fam)) {
              declaredFonts[fam] = [];
            }
          } else if (trimmed.startsWith('asset:') ||
              trimmed.startsWith('- asset:')) {
            var fontAsset =
                trimmed.replaceFirst(RegExp(r'^-?\s*asset:\s*'), '').trim();
            if (fontAsset.contains('#')) {
              fontAsset = fontAsset.substring(0, fontAsset.indexOf('#')).trim();
            }
            fontAsset =
                fontAsset.replaceAll(RegExp(r'''^["']+|["']+$'''), '').trim();
            if (currentFontFamily != null && fontAsset.isNotEmpty) {
              declaredFonts[currentFontFamily]!
                  .add(fontAsset.replaceAll(r'\', '/'));
            }
          }
        }
      }
    } catch (_) {
      // Defensive parsing
    }

    return PackageDescriptor(
      name: name,
      pubspecFile: file,
      packageRootDir: parentDir,
      declaredAssetPatterns: declaredAssets,
      declaredFonts: declaredFonts,
    );
  }

  /// Scans [root] and returns all parsed [PackageDescriptor]s found in the workspace.
  static List<PackageDescriptor> scanAllPackages(Directory root) {
    final files = discoverPubspecFiles(root);
    return files.map(parsePubspec).toList();
  }

  /// Resolves the innermost [PackageDescriptor] owning a specific file on disk.
  static PackageDescriptor? resolveOwningPackage(
    String filePath,
    List<PackageDescriptor> packages,
  ) {
    final canonFile = canonicalizePath(filePath);
    PackageDescriptor? bestMatch;
    int bestMatchLength = -1;

    for (final pkg in packages) {
      final canonPkg = canonicalizePath(pkg.packageRootDir.path);
      if (canonFile.startsWith(canonPkg)) {
        if (canonPkg.length > bestMatchLength) {
          bestMatch = pkg;
          bestMatchLength = canonPkg.length;
        }
      }
    }

    return bestMatch;
  }
}
