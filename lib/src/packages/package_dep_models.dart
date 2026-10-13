import 'dart:io';

import '../utils.dart';

/// Scope of a package dependency inside `pubspec.yaml`.
enum DependencyScope {
  /// Regular runtime dependency under `dependencies:`.
  regular,

  /// Development or build dependency under `dev_dependencies:`.
  dev,
}

/// Helper extension for [DependencyScope] display.
extension DependencyScopeExtension on DependencyScope {
  /// User-friendly label for CLI reporting.
  String get label {
    switch (this) {
      case DependencyScope.regular:
        return '📦 [DEPENDENCY]';
      case DependencyScope.dev:
        return '🛠️ [DEV_DEPENDENCY]';
    }
  }

  /// The YAML section name.
  String get sectionName {
    switch (this) {
      case DependencyScope.regular:
        return 'dependencies';
      case DependencyScope.dev:
        return 'dev_dependencies';
    }
  }
}

/// The type of issue detected for a declared dependency.
enum DependencyIssueType {
  /// The dependency is declared in `pubspec.yaml` but never imported or referenced in code.
  unused,

  /// The dependency is declared more than once in the same `pubspec.yaml` (e.g. redundant or conflicting duplicate).
  duplicate,
}

/// Represents a raw declared dependency extracted from a `pubspec.yaml` file.
class DeclaredDependency {
  /// The name of the package.
  final String name;

  /// The scope where it is declared (`dependencies` or `dev_dependencies`).
  final DependencyScope scope;

  /// The version constraint or specification (e.g. `^1.2.0`, `any`, or path/git summary).
  final String versionConstraint;

  /// Whether this declaration spans multiple lines (e.g. git/path blocks).
  final bool isMultiline;

  /// 1-based start line number in `pubspec.yaml`.
  final int startLine;

  /// 1-based end line number in `pubspec.yaml` (inclusive).
  final int endLine;

  /// The exact raw lines from `pubspec.yaml` for this dependency entry.
  final List<String> rawLines;

  /// Creates a new [DeclaredDependency].
  DeclaredDependency({
    required this.name,
    required this.scope,
    required this.versionConstraint,
    required this.isMultiline,
    required this.startLine,
    required this.endLine,
    required this.rawLines,
  });
}

/// Represents an unused or duplicate dependency issue found during audit.
class UnusedDependencyItem {
  /// Name of the package.
  final String packageName;

  /// The scope (`dependencies` or `dev_dependencies`).
  final DependencyScope scope;

  /// The specific issue found (`unused` or `duplicate`).
  final DependencyIssueType issueType;

  /// The physical `pubspec.yaml` file containing this declaration.
  final File pubspecFile;

  /// Relative path of `pubspec.yaml` from workspace root.
  final String pubspecRelativePath;

  /// Name of the package containing this `pubspec.yaml`.
  final String owningPackageName;

  /// 1-based starting line number in `pubspec.yaml`.
  final int startLine;

  /// 1-based ending line number in `pubspec.yaml` (inclusive).
  final int endLine;

  /// Raw declaration text as written in `pubspec.yaml`.
  final String rawDeclaration;

  /// Human-readable explanation of why this was flagged.
  final String description;

  /// Creates a new [UnusedDependencyItem].
  UnusedDependencyItem({
    required this.packageName,
    required this.scope,
    required this.issueType,
    required this.pubspecFile,
    required this.pubspecRelativePath,
    required this.owningPackageName,
    required this.startLine,
    required this.endLine,
    required this.rawDeclaration,
    required this.description,
  });

  /// Clickable file URI pointing directly to the line in `pubspec.yaml`.
  String get fileUri => toFileUri(pubspecFile.path, line: startLine);

  /// Label tag for terminal reporting.
  String get tag {
    if (issueType == DependencyIssueType.duplicate) {
      return '⚠️ [DUPLICATE]';
    }
    return scope.label;
  }

  /// Serializes the item into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'scope': scope.sectionName,
        'issueType': issueType.name,
        'pubspecPath': pubspecRelativePath,
        'owningPackageName': owningPackageName,
        'startLine': startLine,
        'endLine': endLine,
        'rawDeclaration': rawDeclaration,
        'description': description,
        'fileUri': fileUri,
      };
}

/// Comprehensive report of dependency auditing across all `pubspec.yaml` files.
class PackageDependenciesReport {
  /// All detected unused and duplicate dependency issues.
  final List<UnusedDependencyItem> issues;

  /// Total number of package dependencies scanned across the workspace.
  final int totalDependenciesScanned;

  /// Total number of `pubspec.yaml` files inspected.
  final int scannedPubspecsCount;

  /// Creates a new [PackageDependenciesReport].
  PackageDependenciesReport({
    required this.issues,
    required this.totalDependenciesScanned,
    required this.scannedPubspecsCount,
  });

  /// Filtered list of only unused dependencies.
  List<UnusedDependencyItem> get unusedDependencies =>
      issues.where((i) => i.issueType == DependencyIssueType.unused).toList();

  /// Filtered list of only duplicate dependencies.
  List<UnusedDependencyItem> get duplicateDependencies => issues
      .where((i) => i.issueType == DependencyIssueType.duplicate)
      .toList();

  /// Distinct count of `pubspec.yaml` files having issues.
  int get pubspecsWithIssuesCount =>
      issues.map((i) => canonicalizePath(i.pubspecFile.path)).toSet().length;

  /// Serializes the report into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'totalDependenciesScanned': totalDependenciesScanned,
        'scannedPubspecsCount': scannedPubspecsCount,
        'issuesCount': issues.length,
        'unusedCount': unusedDependencies.length,
        'duplicateCount': duplicateDependencies.length,
        'issues': issues.map((i) => i.toJson()).toList(),
      };
}
