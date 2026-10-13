import 'dart:io';

import '../assets/pubspec_scanner.dart';
import '../utils.dart';
import 'package_dep_models.dart';

/// Callback signature for dependency auditing progress.
typedef DepProgressCallback = void Function(int percent, String message);

/// Primary auditor engine that scans projects for unused and duplicate external dependencies across all `pubspec.yaml` files.
class DependencyAuditor {
  /// The root directory of the workspace or project.
  final Directory workspaceRoot;

  /// Default system and framework packages that are never flagged as unused.
  static const systemPackages = {
    'flutter',
    'flutter_test',
    'flutter_localizations',
    'flutter_web_plugins',
    'sky_engine',
  };

  /// Common code generators, builders, and development tools that run externally via CLI or build_runner.
  static const knownToolAndBuilderPackages = {
    // Linters & analysis
    'lints',
    'flutter_lints',
    'custom_lint',
    'very_good_analysis',
    'dart_code_metrics',
    // Build & Code generators
    'build_runner',
    'build_web_compilers',
    'build_config',
    'build',
    'source_gen',
    'json_serializable',
    'freezed',
    'auto_route_generator',
    'injectable_generator',
    'hive_generator',
    'drift_dev',
    'mobx_codegen',
    'retrofit_generator',
    'flutter_gen',
    'spider',
    // Test utilities
    'test',
    'integration_test',
  };

  /// Creates a new [DependencyAuditor].
  DependencyAuditor({Directory? workspaceRoot})
      : workspaceRoot = workspaceRoot ?? findProjectOrWorkspaceRoot();

  /// Runs the full dependency audit across all `pubspec.yaml` files found in the workspace.
  PackageDependenciesReport run({DepProgressCallback? onProgress}) {
    onProgress?.call(5, 'Discovering pubspec.yaml files across workspace...');
    final pubspecFiles = PubspecScanner.discoverPubspecFiles(workspaceRoot);

    if (pubspecFiles.isEmpty) {
      onProgress?.call(100, 'No pubspec.yaml found');
      return PackageDependenciesReport(
        issues: [],
        totalDependenciesScanned: 0,
        scannedPubspecsCount: 0,
      );
    }

    final allIssues = <UnusedDependencyItem>[];
    int totalScannedDeps = 0;

    final totalPubspecs = pubspecFiles.length;
    for (int pIdx = 0; pIdx < totalPubspecs; pIdx++) {
      final pubFile = pubspecFiles[pIdx];
      final pkgDir = pubFile.parent;
      final relPubPath = getRelativePath(pubFile.path, workspaceRoot.path);

      onProgress?.call(
        10 + (((pIdx + 1) / totalPubspecs) * 30).floor(),
        'Parsing dependencies in $relPubPath (${pIdx + 1}/$totalPubspecs)...',
      );

      // 1. Parse declared dependencies from this specific pubspec.yaml
      final parsedResult = _parsePubspecDependencies(pubFile);
      final declaredList = parsedResult.declared;
      totalScannedDeps += declaredList.length;

      // Add any duplicate issues detected in this file
      allIssues.addAll(parsedResult.duplicateIssues);

      // 2. Resolve .dart files strictly scoped to this package
      // (excluding any subdirectories that have their own pubspec.yaml)
      final scopedDartFiles = _getScopedDartFiles(pkgDir, pubspecFiles);

      // 3. Extract all imported and exported package names from this package's code
      final importedPackageNames = _extractImportedPackages(scopedDartFiles);

      // 4. Inspect build.yaml in this package for builder registrations
      final buildYamlPackages = _extractBuildYamlPackages(pkgDir);

      // 5. Inspect executables in this pubspec.yaml
      final executablePackages = _extractExecutablePackages(pubFile);

      // 6. Audit each non-duplicate declared dependency
      final seenPackagesInThisPubspec = <String>{};

      for (final dep in declaredList) {
        final pkgName = dep.name;

        // Skip if already flagged as duplicate
        if (!seenPackagesInThisPubspec.add('${dep.scope.name}:$pkgName')) {
          continue;
        }

        // Check if protected by guard engines
        if (systemPackages.contains(pkgName)) {
          continue;
        }

        if (dep.scope == DependencyScope.dev &&
            knownToolAndBuilderPackages.contains(pkgName)) {
          continue;
        }

        if (buildYamlPackages.contains(pkgName) ||
            executablePackages.contains(pkgName)) {
          continue;
        }

        // Check active usage in scoped code
        if (!importedPackageNames.contains(pkgName)) {
          final isDev = dep.scope == DependencyScope.dev;
          final desc = isDev
              ? "Dev dependency '$pkgName' is declared under dev_dependencies but never imported in this package's code or tests."
              : "Dependency '$pkgName' is declared under dependencies but never imported or referenced in this package.";

          allIssues.add(UnusedDependencyItem(
            packageName: pkgName,
            scope: dep.scope,
            issueType: DependencyIssueType.unused,
            pubspecFile: pubFile,
            pubspecRelativePath: relPubPath,
            owningPackageName: parsedResult.packageName,
            startLine: dep.startLine,
            endLine: dep.endLine,
            rawDeclaration: dep.rawLines.join('\n'),
            description: desc,
          ));
        }
      }
    }

    onProgress?.call(100, 'Dependency audit completed');

    return PackageDependenciesReport(
      issues: allIssues,
      totalDependenciesScanned: totalScannedDeps,
      scannedPubspecsCount: totalPubspecs,
    );
  }

  /// Parses all declared dependencies and duplicate declarations from [pubFile].
  _ParsedPubspecDependencies _parsePubspecDependencies(File pubFile) {
    final declared = <DeclaredDependency>[];
    final duplicates = <UnusedDependencyItem>[];

    String packageName =
        pubFile.parent.uri.pathSegments.where((s) => s.isNotEmpty).safeLast ??
            'unknown_package';
    final relPubPath = getRelativePath(pubFile.path, workspaceRoot.path);

    if (!pubFile.existsSync()) {
      return _ParsedPubspecDependencies(
        packageName: packageName,
        declared: declared,
        duplicateIssues: duplicates,
      );
    }

    try {
      final lines = pubFile.readAsLinesSync();
      final totalLines = lines.length;

      DependencyScope? currentScope;
      int scopeBaseIndent = -1;

      // Track occurrences for duplicate detection: Map<pkgName, List<DeclaredDependency>>
      final packageOccurrences = <String, List<DeclaredDependency>>{};

      int i = 0;
      while (i < totalLines) {
        final rawLine = lines[i];
        final trimmed = rawLine.trim();
        final lineNum = i + 1; // 1-based

        // Check package name
        if (trimmed.startsWith('name:')) {
          final parts = trimmed.split(':');
          if (parts.length >= 2) {
            final n = parts[1].trim();
            if (n.isNotEmpty) packageName = n;
          }
          i++;
          continue;
        }

        // Skip comments and empty lines at top-level
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          i++;
          continue;
        }

        final indent = rawLine.indexOf(rawLine.trimLeft());

        // Top-level sections (indent == 0)
        if (indent == 0) {
          if (trimmed.startsWith('dependencies:')) {
            currentScope = DependencyScope.regular;
            scopeBaseIndent = 0;
            i++;
            continue;
          } else if (trimmed.startsWith('dev_dependencies:')) {
            currentScope = DependencyScope.dev;
            scopeBaseIndent = 0;
            i++;
            continue;
          } else {
            // Exited dependencies sections
            currentScope = null;
            i++;
            continue;
          }
        }

        // Inside dependencies or dev_dependencies section
        if (currentScope != null) {
          // If indentation reverted to root or a new top-level section started
          if (indent <= scopeBaseIndent) {
            currentScope = null;
            continue;
          }

          // Look for dependency declaration: "  package_name:"
          final depMatch =
              RegExp(r'^(\s+)([a-zA-Z0-9_-]+):(.*)$').firstMatch(rawLine);
          if (depMatch != null) {
            final depIndent = depMatch.group(1)!.length;
            final name = depMatch.group(2)!;
            final rest = depMatch.group(3)!.trim();

            final startLine = lineNum;
            final blockLines = <String>[rawLine];
            bool isMultiline = false;
            String version = rest;

            // Check if multiline block (e.g. path: or git:)
            int nextIdx = i + 1;
            while (nextIdx < totalLines) {
              final nextRaw = lines[nextIdx];
              final nextTrimmed = nextRaw.trim();

              if (nextTrimmed.isEmpty || nextTrimmed.startsWith('#')) {
                nextIdx++;
                continue;
              }

              final nextIndent = nextRaw.indexOf(nextRaw.trimLeft());
              if (nextIndent > depIndent) {
                // Continuation line of this dependency
                isMultiline = true;
                blockLines.add(nextRaw);
                nextIdx++;
              } else {
                break;
              }
            }

            final endLine = nextIdx; // lineNum + blockLines.length - 1
            i = nextIdx; // Advance to next declaration

            final decl = DeclaredDependency(
              name: name,
              scope: currentScope,
              versionConstraint:
                  version.isEmpty ? (isMultiline ? 'custom' : 'any') : version,
              isMultiline: isMultiline,
              startLine: startLine,
              endLine: endLine,
              rawLines: blockLines,
            );

            declared.add(decl);
            packageOccurrences.putIfAbsent(name, () => []).add(decl);
            continue;
          }
        }

        i++;
      }

      // Check duplicates across occurrences in this pubspec.yaml
      for (final entry in packageOccurrences.entries) {
        final pkgName = entry.key;
        final list = entry.value;

        if (list.length > 1) {
          // All occurrences after the first are duplicates!
          for (int d = 1; d < list.length; d++) {
            final dup = list[d];
            final first = list.first;
            duplicates.add(UnusedDependencyItem(
              packageName: pkgName,
              scope: dup.scope,
              issueType: DependencyIssueType.duplicate,
              pubspecFile: pubFile,
              pubspecRelativePath: relPubPath,
              owningPackageName: packageName,
              startLine: dup.startLine,
              endLine: dup.endLine,
              rawDeclaration: dup.rawLines.join('\n'),
              description:
                  "Duplicate declaration of package '$pkgName' (originally declared at L${first.startLine} in ${first.scope.sectionName}).",
            ));
          }
        }
      }
    } catch (_) {
      // Defensive parsing
    }

    return _ParsedPubspecDependencies(
      packageName: packageName,
      declared: declared,
      duplicateIssues: duplicates,
    );
  }

  /// Collects Dart files belonging strictly to [pkgDir], excluding any nested sub-packages having their own `pubspec.yaml`.
  List<File> _getScopedDartFiles(Directory pkgDir, List<File> allPubspecs) {
    final canonPkg = canonicalizePath(pkgDir.path);
    final nestedChildPubspecDirs = allPubspecs
        .where((p) =>
            canonicalizePath(p.path) !=
            canonicalizePath('${pkgDir.path}/pubspec.yaml'))
        .map((p) => canonicalizePath(p.parent.path))
        .where((other) => other.startsWith('$canonPkg/'))
        .toList();

    final results = <File>[];

    void scan(Directory current) {
      final canonCur = canonicalizePath(current.path);

      // If this directory is owned by another nested child pubspec, skip it!
      for (final child in nestedChildPubspecDirs) {
        if (canonCur == child || canonCur.startsWith('$child/')) {
          return;
        }
      }

      try {
        final entities = current.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is Directory) {
            final name =
                entity.uri.pathSegments.where((s) => s.isNotEmpty).safeLast ??
                    '';
            if (ignoredDirNames.contains(name) || name.startsWith('.')) {
              continue;
            }
            scan(entity);
          } else if (entity is File) {
            if (entity.path.endsWith('.dart')) {
              results.add(entity);
            }
          }
        }
      } catch (_) {}
    }

    scan(pkgDir);
    return results;
  }

  /// Extracts all referenced package names from `import 'package:<name>/...'` and `export 'package:<name>/...'`.
  Set<String> _extractImportedPackages(List<File> dartFiles) {
    final imported = <String>{};
    final regex =
        RegExp(r'''(?:import|export)\s+['"]package:([a-zA-Z0-9_-]+)/''');

    for (final f in dartFiles) {
      try {
        final content = f.readAsStringSync();
        for (final match in regex.allMatches(content)) {
          final pkg = match.group(1);
          if (pkg != null && pkg.isNotEmpty) {
            imported.add(pkg);
          }
        }
      } catch (_) {}
    }

    return imported;
  }

  /// Inspects build.yaml for builder dependencies if present.
  Set<String> _extractBuildYamlPackages(Directory pkgDir) {
    final buildYaml = File('${pkgDir.path}/build.yaml');
    if (!buildYaml.existsSync()) return const {};

    final pkgs = <String>{};
    try {
      final content = buildYaml.readAsStringSync();
      // Match builders like "package_name:builder_name"
      final regex = RegExp(r'([a-zA-Z0-9_-]+):[a-zA-Z0-9_-]+');
      for (final m in regex.allMatches(content)) {
        final p = m.group(1);
        if (p != null) pkgs.add(p);
      }
    } catch (_) {}
    return pkgs;
  }

  /// Extracts executable packages declared under `executables:` in pubspec.yaml.
  Set<String> _extractExecutablePackages(File pubFile) {
    if (!pubFile.existsSync()) return const {};
    final pkgs = <String>{};

    try {
      final lines = pubFile.readAsLinesSync();
      bool inExecutables = false;

      for (final line in lines) {
        final trimmed = line.trim();
        final indent = line.indexOf(line.trimLeft());

        if (indent == 0) {
          inExecutables = trimmed.startsWith('executables:');
          continue;
        }

        if (inExecutables && indent > 0) {
          final parts = trimmed.split(':');
          if (parts.isNotEmpty) {
            final name = parts.first.trim();
            if (name.isNotEmpty) pkgs.add(name);
          }
        }
      }
    } catch (_) {}

    return pkgs;
  }
}

class _ParsedPubspecDependencies {
  final String packageName;
  final List<DeclaredDependency> declared;
  final List<UnusedDependencyItem> duplicateIssues;

  _ParsedPubspecDependencies({
    required this.packageName,
    required this.declared,
    required this.duplicateIssues,
  });
}
