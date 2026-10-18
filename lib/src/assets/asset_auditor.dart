import 'dart:io';

import '../utils.dart';
import 'asset_models.dart';
import 'pubspec_scanner.dart';

/// Callback signature for asset auditing progress.
typedef AssetProgressCallback = void Function(int percent, String message);

/// Primary auditor engine that scans Dart and Flutter workspaces for unused assets, images, and fonts.
class AssetAuditor {
  /// The root directory of the workspace or project.
  final Directory workspaceRoot;

  /// Known media and asset file extensions to track.
  static const supportedExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'svg',
    'json',
    'riv',
    'flr',
    'ttf',
    'otf',
    'woff',
    'woff2',
    'mp3',
    'mp4',
    'wav',
  };

  /// Creates a new [AssetAuditor].
  AssetAuditor({Directory? workspaceRoot})
      : workspaceRoot = workspaceRoot ?? findProjectOrWorkspaceRoot();

  /// Runs the full asset audit across all packages discovered in the workspace.
  AssetAnalysisReport run({AssetProgressCallback? onProgress}) {
    onProgress?.call(5, 'Discovering pubspec.yaml packages...');
    final packages = PubspecScanner.scanAllPackages(workspaceRoot);

    if (packages.isEmpty) {
      onProgress?.call(100, 'No pubspec.yaml found');
      return AssetAnalysisReport(
        unusedAssets: [],
        scannedPackages: [],
        totalScannedAssets: 0,
        totalReclaimableBytes: 0,
        totalReclaimableFormatted: '0 B',
      );
    }

    onProgress?.call(15, 'Indexing physical asset files...');
    final physicalFiles = _collectAllAssetFiles(packages);

    if (physicalFiles.isEmpty) {
      onProgress?.call(100, 'No asset files found');
      return AssetAnalysisReport(
        unusedAssets: [],
        scannedPackages: packages,
        totalScannedAssets: 0,
        totalReclaimableBytes: 0,
        totalReclaimableFormatted: '0 B',
      );
    }

    onProgress?.call(35, 'Indexing Dart source code across workspace...');
    final codeCorpus = _buildWorkspaceCodeCorpus(workspaceRoot);

    onProgress?.call(55, 'Auditing asset usage and references...');
    final unusedAssets = <UnusedAssetItem>[];
    int totalBytes = 0;

    // Map base assets to their resolution variants (e.g., 2.0x/, 3.0x/)
    final variantRegex = RegExp(r'/(?:[0-9]+(?:\.[0-9]+)?x)/([^/]+)$');
    final usedBaseImagePaths = <String>{};

    // First pass: Audit primary assets and font families
    final total = physicalFiles.length;
    for (int i = 0; i < total; i++) {
      final file = physicalFiles[i];
      final ownerPkg =
          PubspecScanner.resolveOwningPackage(file.path, packages) ??
              packages.first;

      final relPackage =
          getRelativePath(file.path, ownerPkg.packageRootDir.path);
      final ext =
          file.uri.pathSegments.safeLast?.split('.').safeLast?.toLowerCase() ??
              '';
      final category = AssetCategoryExtension.fromExtension(ext);

      bool isUsed = false;

      if (category == AssetCategory.font) {
        isUsed = _isFontUsed(file, ownerPkg, codeCorpus);
      } else {
        isUsed = _isAssetUsed(
          file: file,
          relPackage: relPackage,
          ownerPkg: ownerPkg,
          codeCorpus: codeCorpus,
        );
      }

      if (isUsed) {
        // Mark base file path as used
        usedBaseImagePaths.add(canonicalizePath(file.path));
        // If this itself is a base file, also register its canonical path
        final baseName = file.uri.pathSegments.safeLast ?? '';
        final parentDir = file.parent.path.replaceAll(r'\', '/');
        usedBaseImagePaths.add(canonicalizePath('$parentDir/$baseName'));
      }

      if (i % 25 == 0 || i == total - 1) {
        final pct = 55 + (((i + 1) / total) * 35).floor();
        onProgress?.call(pct, 'Auditing assets (${i + 1}/$total)...');
      }
    }

    // Second pass: Mark resolution variants as used if their parent/base image is used
    for (final file in physicalFiles) {
      final ownerPkg =
          PubspecScanner.resolveOwningPackage(file.path, packages) ??
              packages.first;
      final relPackage =
          getRelativePath(file.path, ownerPkg.packageRootDir.path)
              .replaceAll(r'\', '/');
      final ext =
          file.uri.pathSegments.safeLast?.split('.').safeLast?.toLowerCase() ??
              '';
      final category = AssetCategoryExtension.fromExtension(ext);

      final vMatch = variantRegex.firstMatch(relPackage);
      bool isVariant = vMatch != null;
      bool isUsed = false;

      if (category == AssetCategory.font) {
        isUsed = _isFontUsed(file, ownerPkg, codeCorpus);
      } else if (isVariant) {
        // Resolve parent base file
        final fileName = vMatch.group(1)!;
        // The base image is located in the grandparent directory
        final baseFile = File('${file.parent.parent.path}/$fileName');
        if (usedBaseImagePaths.contains(canonicalizePath(baseFile.path))) {
          isUsed = true;
        } else {
          // Check if variant itself was specifically referenced
          isUsed = _isAssetUsed(
            file: file,
            relPackage: relPackage,
            ownerPkg: ownerPkg,
            codeCorpus: codeCorpus,
          );
        }
      } else {
        isUsed = usedBaseImagePaths.contains(canonicalizePath(file.path));
      }

      if (!isUsed) {
        int size = 0;
        try {
          size = file.lengthSync();
        } catch (_) {}

        final relWorkspace = getRelativePath(file.path, workspaceRoot.path);
        final isExplicit = _isExplicitlyDeclared(relPackage, ownerPkg);

        totalBytes += size;
        unusedAssets.add(UnusedAssetItem(
          path: relWorkspace,
          packageRelativePath: relPackage,
          absolutePath: file.path,
          fileUri: toFileUri(file.path),
          sizeInBytes: size,
          sizeFormatted: formatByteSize(size),
          category: category,
          ownerPackage: ownerPkg,
          isExplicitInPubspec: isExplicit,
        ));
      }
    }

    onProgress?.call(100, 'Asset audit completed');

    return AssetAnalysisReport(
      unusedAssets: unusedAssets,
      scannedPackages: packages,
      totalScannedAssets: physicalFiles.length,
      totalReclaimableBytes: totalBytes,
      totalReclaimableFormatted: formatByteSize(totalBytes),
    );
  }

  /// Collects all physical asset files from disk based on declared patterns or standard asset directories.
  List<File> _collectAllAssetFiles(List<PackageDescriptor> packages) {
    final seen = <String>{};
    final files = <File>[];

    for (final pkg in packages) {
      final root = pkg.packageRootDir;
      final dirsToScan = <Directory>{};

      // 1. Scan declared asset patterns
      for (final rawPat in pkg.declaredAssetPatterns) {
        final cleanPat = cleanInputPath(rawPat);
        final entity =
            FileSystemEntity.isDirectorySync('${root.path}/$cleanPat')
                ? Directory('${root.path}/$cleanPat')
                : File('${root.path}/$cleanPat');

        if (entity is Directory && entity.existsSync()) {
          dirsToScan.add(entity);
        } else if (entity is File && entity.existsSync()) {
          final canon = canonicalizePath(entity.path);
          if (seen.add(canon)) {
            files.add(entity);
          }
        }
      }

      // 2. Scan standard 'assets' directory if it exists
      final defaultAssetsDir = Directory('${root.path}/assets');
      if (defaultAssetsDir.existsSync()) {
        dirsToScan.add(defaultAssetsDir);
      }

      // 3. Scan declared font directories
      for (final fontList in pkg.declaredFonts.values) {
        for (final fontPath in fontList) {
          final fontFile = File('${root.path}/$fontPath');
          if (fontFile.existsSync()) {
            final canon = canonicalizePath(fontFile.path);
            if (seen.add(canon)) {
              files.add(fontFile);
            }
          }
        }
      }

      // Recursively gather all media files in targeted directories
      for (final dir in dirsToScan) {
        _walkAssetDirectory(dir, seen, files);
      }
    }

    return files;
  }

  void _walkAssetDirectory(Directory dir, Set<String> seen, List<File> files) {
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final e in entities) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.safeLast ?? '';
        if (name.startsWith('.')) continue; // Skip hidden files like .DS_Store
        final ext = name.split('.').safeLast?.toLowerCase() ?? '';
        if (supportedExtensions.contains(ext)) {
          final canon = canonicalizePath(e.path);
          if (seen.add(canon)) {
            files.add(e);
          }
        }
      }
    } catch (_) {}
  }

  /// Builds a combined, comment-stripped text corpus of all Dart files in the workspace.
  String _buildWorkspaceCodeCorpus(Directory root) {
    final dartFiles = walkDartFiles(root);
    final buffer = StringBuffer();

    for (final f in dartFiles) {
      try {
        final raw = f.readAsStringSync();
        // Strip single & multi-line comments to avoid false-positives from dead commented-out code
        buffer.writeln(stripCommentsAndStringsPreservingLiterals(raw));
      } catch (_) {}
    }

    return buffer.toString();
  }

  /// Checks if an asset file is actively referenced in the code corpus.
  bool _isAssetUsed({
    required File file,
    required String relPackage,
    required PackageDescriptor ownerPkg,
    required String codeCorpus,
  }) {
    final fileName = file.uri.pathSegments.safeLast ?? '';
    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    // 1. Direct path check (e.g. 'assets/images/logo.png')
    final normRel = relPackage.replaceAll(r'\', '/');
    if (codeCorpus.contains(normRel)) return true;

    // 2. Direct filename check (e.g. 'logo.png')
    if (codeCorpus.contains(fileName)) return true;

    // 3. Cross-package reference (e.g. 'packages/my_pkg/assets/images/logo.png')
    final crossPkgRef = 'packages/${ownerPkg.name}/$normRel';
    if (codeCorpus.contains(crossPkgRef)) return true;

    // 4. Code generator identifiers (flutter_gen / spider)
    // Converts snake_case or kebab-case (e.g. 'ic_user_avatar.png') to camelCase 'icUserAvatar'
    final camelCase = _toCamelCase(nameWithoutExt);
    if (camelCase.length >= 3) {
      // Must match as an identifier boundary in Dart
      final idPattern = RegExp('\\b$camelCase\\b');
      if (idPattern.hasMatch(codeCorpus)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if a font file is used via its declared fontFamily or filename.
  bool _isFontUsed(File file, PackageDescriptor ownerPkg, String codeCorpus) {
    final fileName = file.uri.pathSegments.safeLast ?? '';

    // Check if filename is directly referenced (e.g. 'assets/fonts/Cairo.ttf' or 'Cairo.ttf')
    if (codeCorpus.contains(fileName)) return true;

    // Check if any declared font family containing this asset is referenced in code
    final normPath = getRelativePath(file.path, ownerPkg.packageRootDir.path)
        .replaceAll(r'\', '/');

    for (final entry in ownerPkg.declaredFonts.entries) {
      final family = entry.key;
      final assets = entry.value;

      if (assets.any((a) => a.replaceAll(r'\', '/') == normPath)) {
        // If the font family name is referenced as a string literal in Dart code (e.g. fontFamily: 'MyFont' or "MyFont")
        final familyPattern = RegExp('[\'"]${RegExp.escape(family)}[\'"]');
        if (familyPattern.hasMatch(codeCorpus)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Converts snake_case, kebab-case, or space-separated names to camelCase for flutter_gen matching.
  static String _toCamelCase(String text) {
    final parts =
        text.split(RegExp(r'[-_\s]+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return text;
    final first = parts.first.toLowerCase();
    final rest = parts.skip(1).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join('');
    return '$first$rest';
  }

  /// Checks if a file path was explicitly declared by full path in pubspec.yaml (assets or fonts).
  bool _isExplicitlyDeclared(String relPackage, PackageDescriptor pkg) {
    final norm = relPackage.replaceAll(r'\', '/');
    if (pkg.declaredAssetPatterns
        .any((pat) => pat.replaceAll(r'\', '/') == norm)) {
      return true;
    }
    for (final fontList in pkg.declaredFonts.values) {
      if (fontList.any((f) => f.replaceAll(r'\', '/') == norm)) {
        return true;
      }
    }
    return false;
  }
}

/// Strips comments from Dart source code while preserving string literals so asset paths remain intact.
String stripCommentsAndStringsPreservingLiterals(String source) {
  final sb = StringBuffer();
  final len = source.length;
  int i = 0;

  while (i < len) {
    final c = source[i];

    // Single-line comment
    if (c == '/' && i + 1 < len && source[i + 1] == '/') {
      i += 2;
      while (i < len && source[i] != '\n') {
        i++;
      }
      sb.write(' ');
      continue;
    }

    // Block comment
    if (c == '/' && i + 1 < len && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < len && !(source[i] == '*' && source[i + 1] == '/')) {
        if (source[i] == '\n') sb.write('\n');
        i++;
      }
      i += 2; // skip */
      sb.write(' ');
      continue;
    }

    sb.write(c);
    i++;
  }

  return sb.toString();
}
