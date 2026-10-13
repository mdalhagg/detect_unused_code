import 'dart:io';

/// Categories of assets tracked by the auditor.
enum AssetCategory {
  /// Raster images (PNG, JPG, JPEG, WEBP, GIF, BMP).
  image,

  /// Vector graphics (SVG).
  vector,

  /// Animations (Lottie JSON, Rive).
  animation,

  /// Typography and font files (TTF, OTF, WOFF, WOFF2).
  font,

  /// Miscellaneous asset files (JSON, audio, video, etc.).
  other,
}

/// Helper extension for [AssetCategory] display names and formatting.
extension AssetCategoryExtension on AssetCategory {
  /// Short label in uppercase with emoji icon for terminal display.
  String get label {
    switch (this) {
      case AssetCategory.image:
        return '🖼️ [IMAGE]';
      case AssetCategory.vector:
        return '📐 [VECTOR]';
      case AssetCategory.animation:
        return '🎬 [ANIMATION]';
      case AssetCategory.font:
        return '🔤 [FONT]';
      case AssetCategory.other:
        return '📄 [OTHER]';
    }
  }

  /// Categorizes a file by its extension.
  static AssetCategory fromExtension(String ext) {
    final clean = ext.toLowerCase().replaceFirst('.', '');
    switch (clean) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'bmp':
        return AssetCategory.image;
      case 'svg':
        return AssetCategory.vector;
      case 'json':
      case 'riv':
      case 'flr':
        return AssetCategory.animation;
      case 'ttf':
      case 'otf':
      case 'woff':
      case 'woff2':
        return AssetCategory.font;
      default:
        return AssetCategory.other;
    }
  }
}

/// Represents a package within a single or multi-package / monorepo workspace.
class PackageDescriptor {
  /// Name of the package from its `pubspec.yaml`.
  final String name;

  /// The physical `pubspec.yaml` file.
  final File pubspecFile;

  /// The root directory containing this package.
  final Directory packageRootDir;

  /// List of raw asset patterns declared under `flutter -> assets` in this pubspec.
  final List<String> declaredAssetPatterns;

  /// Map of font family names to their list of declared asset paths under `flutter -> fonts`.
  final Map<String, List<String>> declaredFonts;

  /// Creates a new [PackageDescriptor].
  PackageDescriptor({
    required this.name,
    required this.pubspecFile,
    required this.packageRootDir,
    this.declaredAssetPatterns = const [],
    this.declaredFonts = const {},
  });

  /// Serializes package information into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'name': name,
        'pubspecPath': pubspecFile.path.replaceAll(r'\', '/'),
        'packageRootDir': packageRootDir.path.replaceAll(r'\', '/'),
        'declaredAssetPatterns': declaredAssetPatterns,
        'declaredFonts': declaredFonts,
      };

  @override
  String toString() => 'PackageDescriptor($name @ ${packageRootDir.path})';
}

/// Represents an unused asset file discovered during auditing.
class UnusedAssetItem {
  /// File path relative to the root workspace.
  final String path;

  /// File path relative to the owning package root.
  final String packageRelativePath;

  /// Absolute file system path.
  final String absolutePath;

  /// Clickable `file://` URI string for IDE navigation.
  final String fileUri;

  /// Size of the asset file in bytes.
  final int sizeInBytes;

  /// Human-readable formatted size (e.g. `1.45 MB`, `320.0 KB`).
  final String sizeFormatted;

  /// Category of the asset.
  final AssetCategory category;

  /// The package owning this asset.
  final PackageDescriptor ownerPackage;

  /// Whether this specific file was explicitly listed by full path in `pubspec.yaml`.
  final bool isExplicitInPubspec;

  /// Creates a new [UnusedAssetItem].
  UnusedAssetItem({
    required this.path,
    required this.packageRelativePath,
    required this.absolutePath,
    required this.fileUri,
    required this.sizeInBytes,
    required this.sizeFormatted,
    required this.category,
    required this.ownerPackage,
    required this.isExplicitInPubspec,
  });

  /// Serializes the unused asset item into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'path': path,
        'packageRelativePath': packageRelativePath,
        'absolutePath': absolutePath,
        'fileUri': fileUri,
        'sizeInBytes': sizeInBytes,
        'sizeFormatted': sizeFormatted,
        'category': category.name,
        'packageName': ownerPackage.name,
        'pubspecPath': ownerPackage.pubspecFile.path.replaceAll(r'\', '/'),
        'isExplicitInPubspec': isExplicitInPubspec,
      };
}

/// Comprehensive audit report of assets across all packages in the workspace.
class AssetAnalysisReport {
  /// List of unused assets found.
  final List<UnusedAssetItem> unusedAssets;

  /// All packages discovered and inspected.
  final List<PackageDescriptor> scannedPackages;

  /// Total count of physical asset files found across the project.
  final int totalScannedAssets;

  /// Total reclaimable disk space in bytes if all unused assets are deleted.
  final int totalReclaimableBytes;

  /// Human-readable formatted string of total reclaimable disk space.
  final String totalReclaimableFormatted;

  /// Creates a new [AssetAnalysisReport].
  AssetAnalysisReport({
    required this.unusedAssets,
    required this.scannedPackages,
    required this.totalScannedAssets,
    required this.totalReclaimableBytes,
    required this.totalReclaimableFormatted,
  });

  /// Serializes the asset report into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'totalScannedAssets': totalScannedAssets,
        'unusedAssetsCount': unusedAssets.length,
        'totalReclaimableBytes': totalReclaimableBytes,
        'totalReclaimableFormatted': totalReclaimableFormatted,
        'scannedPackages': scannedPackages.map((p) => p.toJson()).toList(),
        'unusedAssets': unusedAssets.map((a) => a.toJson()).toList(),
      };
}

/// Formats a byte size into a human-readable string (B, KB, MB, GB).
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
