import 'dart:convert';
import 'dart:io';

import '../backup/backup_manager.dart';
import '../backup/backup_manifest.dart';
import '../models.dart';
import '../utils.dart';

/// Represents a compiler or analyzer diagnostic issue found during post-cleanup health checks.
class HealthIssue {
  /// Severity of the diagnostic (e.g. ERROR, WARNING).
  final String severity;

  /// Dart analyzer diagnostic code name (e.g. `uri_does_not_exist`).
  final String code;

  /// Problem description message.
  final String message;

  /// Absolute file path where the issue is located.
  final String file;

  /// 1-based line number.
  final int line;

  /// 1-based column number.
  final int column;

  /// The target URI extracted from `uri_does_not_exist`, if available.
  final String? uri;

  /// Creates a new [HealthIssue].
  HealthIssue({
    required this.severity,
    required this.code,
    required this.message,
    required this.file,
    required this.line,
    required this.column,
    this.uri,
  });

  /// Whether this issue is an invalid or dangling URI reference to a deleted/missing file.
  bool get isDanglingUri =>
      code == 'uri_does_not_exist' ||
      message.contains("Target of URI doesn't exist");

  @override
  String toString() => '$file:$line - $message';
}

/// Comprehensive health check result after running Dart analysis.
class HealthCheckResult {
  /// List of compiler errors detected.
  final List<HealthIssue> errors;

  /// List of analyzer warnings detected.
  final List<HealthIssue> warnings;

  /// Creates a new [HealthCheckResult].
  HealthCheckResult({
    this.errors = const [],
    this.warnings = const [],
  });

  /// Whether any compilation errors are present.
  bool get hasErrors => errors.isNotEmpty;

  /// Whether any errors are caused by dangling/missing URI directives.
  bool get hasDanglingUris => errors.any((e) => e.isDanglingUri);

  /// String formatted error messages.
  List<String> get errorMessages => errors.map((e) => e.toString()).toList();
}

/// Describes a dangling directive (import/export/part) that was safely removed.
class RemovedDirectiveItem {
  /// Project-relative path of the modified file.
  final String file;

  /// Line number where the directive was removed.
  final int line;

  /// The text snippet of the removed directive.
  final String directive;

  /// Target missing URI that triggered removal.
  final String targetUri;

  /// Creates a new [RemovedDirectiveItem].
  RemovedDirectiveItem({
    required this.file,
    required this.line,
    required this.directive,
    required this.targetUri,
  });
}

/// Summary report produced after executing a code cleanup operation.
class CleanResult {
  /// The action name performed.
  final String action;

  /// Whether the cleanup completed successfully.
  final bool success;

  /// List of files that were completely deleted from disk.
  final List<String> deletedFiles;

  /// List of files whose contents were modified.
  final List<String> modifiedFiles;

  /// Total count of dead code items, blocks, or declarations removed.
  final int totalItemsCleaned;

  /// The backup snapshot created prior to cleanup, if backups were enabled.
  final BackupManifest? backup;

  /// Whether post-cleanup compilation/analysis verification passed.
  final bool verificationPassed;

  /// Any compiler or analyzer errors found during post-cleanup verification.
  final List<String> verificationIssues;

  /// Creates a new [CleanResult].
  CleanResult({
    required this.action,
    required this.success,
    this.deletedFiles = const [],
    this.modifiedFiles = const [],
    this.totalItemsCleaned = 0,
    this.backup,
    this.verificationPassed = true,
    this.verificationIssues = const [],
  });
}

/// Orchestrates surgical code cleanup, dead element removal, and safe refactorings.
class CodeCleaner {
  /// Root directory of the target project.
  final Directory projectRoot;

  /// Backup manager handling snapshot creation and rollbacks.
  final BackupManager backupManager;

  /// Creates a new [CodeCleaner] for [projectRoot].
  CodeCleaner(this.projectRoot) : backupManager = BackupManager(projectRoot);

  /// Resolves a file path either as an absolute path or relative to [projectRoot].
  File resolveFile(String path) {
    final direct = File(path);
    if (direct.existsSync()) return direct;
    final rel = File('${projectRoot.path}/$path');
    if (rel.existsSync()) return rel;
    return direct;
  }

  /// Cleans all detected safe issues in one cohesive pass with a single snapshot backup.
  CleanResult cleanAll({
    List<CommentedFileResult> commentedFiles = const [],
    List<CommentedFileResult> filesWithDeadBlocks = const [],
    List<UnusedClassResult> deadClasses = const [],
    List<UnusedClassResult> internalClasses = const [],
    List<TodoItemResult> todos = const [],
    List<DiagnosticIssueResult> unusedImports = const [],
    List<DiagnosticIssueResult> deadCodeItems = const [],
    bool dryRun = false,
    bool createBackup = true,
  }) {
    final allFilesToBackup = <File>{};
    final filesMarkedForDeletion = <String>{};

    for (final f in commentedFiles) {
      final file = resolveFile(f.absolutePath);
      if (file.existsSync()) {
        allFilesToBackup.add(file);
        filesMarkedForDeletion.add(file.path);
      }
    }
    for (final b in filesWithDeadBlocks) {
      final file = resolveFile(b.absolutePath);
      if (file.existsSync()) allFilesToBackup.add(file);
    }
    for (final c in deadClasses) {
      final file = resolveFile(c.file);
      if (file.existsSync()) allFilesToBackup.add(file);
    }
    for (final c in internalClasses) {
      final file = resolveFile(c.file);
      if (file.existsSync()) allFilesToBackup.add(file);
    }
    for (final t in todos) {
      final file = resolveFile(t.absolutePath);
      if (file.existsSync()) allFilesToBackup.add(file);
    }
    for (final d in unusedImports) {
      final file = resolveFile(d.absolutePath);
      if (file.existsSync()) allFilesToBackup.add(file);
    }
    for (final d in deadCodeItems) {
      final file = resolveFile(d.absolutePath);
      if (file.existsSync()) allFilesToBackup.add(file);
    }

    BackupManifest? manifest;
    if (!dryRun && createBackup && allFilesToBackup.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Clean all detected unused code and dead elements',
        filesToBackup: allFilesToBackup.toList(),
        filesMarkedForDeletion: filesMarkedForDeletion,
      );
    }

    final deleted = <String>{};
    final modified = <String>{};
    int totalCleaned = 0;

    if (commentedFiles.isNotEmpty) {
      final res = cleanCommentedFiles(commentedFiles,
          dryRun: dryRun, createBackup: false);
      deleted.addAll(res.deletedFiles);
      totalCleaned += res.totalItemsCleaned;
    }
    if (filesWithDeadBlocks.isNotEmpty) {
      final res = cleanDeadBlocks(filesWithDeadBlocks,
          dryRun: dryRun, createBackup: false);
      modified.addAll(res.modifiedFiles);
      totalCleaned += res.totalItemsCleaned;
    }
    if (deadClasses.isNotEmpty) {
      final res =
          cleanDeadClasses(deadClasses, dryRun: dryRun, createBackup: false);
      deleted.addAll(res.deletedFiles);
      modified.addAll(res.modifiedFiles);
      totalCleaned += res.totalItemsCleaned;
    }
    if (internalClasses.isNotEmpty) {
      final res = privatizeInternalClasses(internalClasses,
          dryRun: dryRun, createBackup: false);
      modified.addAll(res.modifiedFiles);
      totalCleaned += res.totalItemsCleaned;
    }
    if (todos.isNotEmpty) {
      final res = cleanTodos(todos, dryRun: dryRun, createBackup: false);
      modified.addAll(res.modifiedFiles);
      totalCleaned += res.totalItemsCleaned;
    }
    if (unusedImports.isNotEmpty) {
      final res = cleanUnusedImports(unusedImports,
          dryRun: dryRun, createBackup: false);
      modified.addAll(res.modifiedFiles);
      totalCleaned += res.totalItemsCleaned;
    }
    if (deadCodeItems.isNotEmpty) {
      final res = cleanDeadNullAware(deadCodeItems,
          dryRun: dryRun, createBackup: false);
      modified.addAll(res.modifiedFiles);
      totalCleaned += res.totalItemsCleaned;
    }

    return CleanResult(
      action: 'Clean All Unused Code',
      success: true,
      deletedFiles: deleted.toList(),
      modifiedFiles: modified.toList(),
      totalItemsCleaned: totalCleaned,
      backup: manifest,
    );
  }

  /// Deletes fully commented-out files (90%+ comments).
  CleanResult cleanCommentedFiles(
    List<CommentedFileResult> files, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    if (files.isEmpty) {
      return CleanResult(action: 'Clean Commented Files', success: true);
    }

    final targetFiles = files
        .map((f) => File(f.absolutePath))
        .where((f) => f.existsSync())
        .toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Delete fully commented-out files',
        filesToBackup: targetFiles,
        filesMarkedForDeletion: targetFiles.map((f) => f.path),
      );
    }

    final deleted = <String>[];
    for (final f in files) {
      final file = File(f.absolutePath);
      if (file.existsSync()) {
        if (!dryRun) {
          file.deleteSync();
        }
        deleted.add(f.file);
      }
    }

    return CleanResult(
      action: 'Clean Commented Files',
      success: true,
      deletedFiles: deleted,
      totalItemsCleaned: deleted.length,
      backup: manifest,
    );
  }

  /// Removes dead code blocks from active files.
  CleanResult cleanDeadBlocks(
    List<CommentedFileResult> filesWithBlocks, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    final validTargets =
        filesWithBlocks.where((f) => f.blocks.isNotEmpty).toList();
    if (validTargets.isEmpty) {
      return CleanResult(action: 'Clean Dead Blocks', success: true);
    }

    final targetFiles = validTargets
        .map((f) => File(f.absolutePath))
        .where((f) => f.existsSync())
        .toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Remove dead code blocks',
        filesToBackup: targetFiles,
      );
    }

    final modified = <String>[];
    int removedBlocksCount = 0;

    for (final f in validTargets) {
      final file = File(f.absolutePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));
      // Sort blocks from bottom to top so line indexes remain stable during removal
      final sortedBlocks = List<CommentBlockResult>.from(f.blocks)
        ..sort((a, b) => b.startLine.compareTo(a.startLine));

      for (final block in sortedBlocks) {
        final startIdx = block.startLine - 1;
        final count = (block.endLine - block.startLine) + 1;
        if (startIdx >= 0 && (startIdx + count) <= lines.length) {
          lines.removeRange(startIdx, startIdx + count);
          removedBlocksCount++;
        }
      }

      if (!dryRun) {
        file.writeAsStringSync(lines.join('\n'));
      }
      modified.add(f.file);
    }

    return CleanResult(
      action: 'Clean Dead Blocks',
      success: true,
      modifiedFiles: modified,
      totalItemsCleaned: removedBlocksCount,
      backup: manifest,
    );
  }

  /// Removes unused and dead class declarations and their bodies.
  CleanResult cleanDeadClasses(
    List<UnusedClassResult> deadClasses, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    if (deadClasses.isEmpty) {
      return CleanResult(action: 'Clean Dead Classes', success: true);
    }

    final byFile = <String, List<UnusedClassResult>>{};
    for (final c in deadClasses) {
      byFile.putIfAbsent(c.file, () => []).add(c);
    }

    final targetFiles =
        byFile.keys.map((p) => File(p)).where((f) => f.existsSync()).toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Remove dead classes',
        filesToBackup: targetFiles,
      );
    }

    final modified = <String>[];
    final deleted = <String>[];
    int cleanedCount = 0;

    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final classes = entry.value;
      final file = File(filePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));

      // Sort classes from bottom of the file to top
      classes.sort((a, b) => b.line.compareTo(a.line));

      for (final c in classes) {
        final declIndex = _findDeclarationLine(lines, c.name, c.line);
        if (declIndex == -1) {
          continue;
        }

        // Include any annotations and doc comments immediately preceding the class
        int startIndex = declIndex;
        while (startIndex > 0) {
          final prev = lines[startIndex - 1].trim();
          if (prev.startsWith('@') ||
              prev.startsWith('///') ||
              prev.startsWith('//')) {
            startIndex--;
          } else {
            break;
          }
        }

        final endIndex = _findDeclarationEndLine(lines, declIndex);
        if (endIndex != -1 &&
            endIndex >= declIndex &&
            endIndex < lines.length) {
          lines.removeRange(startIndex, endIndex + 1);
          cleanedCount++;
        }
      }

      // Check if file is now essentially empty (only whitespace/imports left)
      final remainingCode = lines.join('\n').trim();
      final hasRealCode = remainingCode.split('\n').any((l) {
        final t = l.trim();
        return t.isNotEmpty &&
            !t.startsWith('//') &&
            !t.startsWith('import ') &&
            !t.startsWith('export ') &&
            !t.startsWith('part ');
      });

      if (!hasRealCode && remainingCode.length < 150) {
        if (!dryRun) {
          file.deleteSync();
        }
        deleted.add(classes.first.relPath);
      } else {
        if (!dryRun) {
          file.writeAsStringSync(lines.join('\n'));
        }
        modified.add(classes.first.relPath);
      }
    }

    return CleanResult(
      action: 'Clean Dead Classes',
      success: true,
      deletedFiles: deleted,
      modifiedFiles: modified,
      totalItemsCleaned: cleanedCount,
      backup: manifest,
    );
  }

  /// Converts public classes used only within their declaring file into private (_) classes.
  CleanResult privatizeInternalClasses(
    List<UnusedClassResult> internalClasses, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    if (internalClasses.isEmpty) {
      return CleanResult(action: 'Privatize Internal Classes', success: true);
    }

    final byFile = <String, List<UnusedClassResult>>{};
    for (final c in internalClasses) {
      byFile.putIfAbsent(c.file, () => []).add(c);
    }

    final targetFiles =
        byFile.keys.map((p) => File(p)).where((f) => f.existsSync()).toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Convert file-internal classes to private (_)',
        filesToBackup: targetFiles,
      );
    }

    final modified = <String>[];
    int privatizedCount = 0;

    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final classes = entry.value;
      final file = File(filePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      var updated = content;
      for (final c in classes) {
        if (c.name.startsWith('_')) {
          continue;
        }
        final pattern = RegExp(r'\b' + RegExp.escape(c.name) + r'\b');
        updated = updated.replaceAll(pattern, '_${c.name}');
        privatizedCount++;
      }

      if (!dryRun && updated != content) {
        file.writeAsStringSync(updated);
      }
      modified.add(classes.first.relPath);
    }

    return CleanResult(
      action: 'Privatize Internal Classes',
      success: true,
      modifiedFiles: modified,
      totalItemsCleaned: privatizedCount,
      backup: manifest,
    );
  }

  /// Removes pending TODO comments and task directives from files.
  CleanResult cleanTodos(
    List<TodoItemResult> todos, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    if (todos.isEmpty) {
      return CleanResult(action: 'Clean TODO Comments', success: true);
    }

    final byFile = <String, List<TodoItemResult>>{};
    for (final t in todos) {
      byFile.putIfAbsent(t.absolutePath, () => []).add(t);
    }

    final targetFiles =
        byFile.keys.map((p) => File(p)).where((f) => f.existsSync()).toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Remove TODO comments',
        filesToBackup: targetFiles,
      );
    }

    final modified = <String>[];
    int removedCount = 0;

    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final fileTodos = entry.value;
      final file = File(filePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));
      // Sort todos from bottom to top
      fileTodos.sort((a, b) => b.line.compareTo(a.line));

      for (final t in fileTodos) {
        final lineIdx = t.line - 1;
        if (lineIdx < 0 || lineIdx >= lines.length) {
          continue;
        }

        final line = lines[lineIdx];
        final trimmed = line.trim();

        if (trimmed.startsWith('//') ||
            trimmed.startsWith('/*') ||
            trimmed.startsWith('*')) {
          // If the entire line is the TODO comment, remove the line
          lines.removeAt(lineIdx);
          removedCount++;
        } else if (line.contains('//')) {
          // Inline comment: strip the comment portion only
          final idx = line.indexOf('//');
          lines[lineIdx] = line.substring(0, idx).trimRight();
          removedCount++;
        }
      }

      if (!dryRun) {
        file.writeAsStringSync(lines.join('\n'));
      }
      modified.add(fileTodos.first.file);
    }

    return CleanResult(
      action: 'Clean TODO Comments',
      success: true,
      modifiedFiles: modified,
      totalItemsCleaned: removedCount,
      backup: manifest,
    );
  }

  /// Removes unused/unnecessary imports across target files.
  CleanResult cleanUnusedImports(
    List<DiagnosticIssueResult> unusedImports, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    if (unusedImports.isEmpty) {
      return CleanResult(action: 'Clean Unused Imports', success: true);
    }

    final byFile = <String, List<DiagnosticIssueResult>>{};
    for (final d in unusedImports) {
      byFile.putIfAbsent(d.absolutePath, () => []).add(d);
    }

    final targetFiles =
        byFile.keys.map((p) => File(p)).where((f) => f.existsSync()).toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Remove unused imports',
        filesToBackup: targetFiles,
      );
    }

    final modified = <String>[];
    int cleanedCount = 0;

    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final imports = entry.value;
      final file = File(filePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));
      // Sort bottom to top
      imports.sort((a, b) => b.line.compareTo(a.line));

      for (final item in imports) {
        final lineIdx = item.line - 1;
        if (lineIdx >= 0 && lineIdx < lines.length) {
          final line = lines[lineIdx].trim();
          if (line.startsWith('import ') || line.contains('import ')) {
            lines.removeAt(lineIdx);
            cleanedCount++;
          }
        }
      }

      if (!dryRun) {
        file.writeAsStringSync(lines.join('\n'));
      }
      modified.add(imports.first.file);
    }

    return CleanResult(
      action: 'Clean Unused Imports',
      success: true,
      modifiedFiles: modified,
      totalItemsCleaned: cleanedCount,
      backup: manifest,
    );
  }

  /// Cleans dead null-aware expressions by replacing `?.` with `.`.
  CleanResult cleanDeadNullAware(
    List<DiagnosticIssueResult> deadNullAwareItems, {
    bool dryRun = false,
    bool createBackup = true,
  }) {
    if (deadNullAwareItems.isEmpty) {
      return CleanResult(
          action: 'Clean Dead Null-Aware Expressions', success: true);
    }

    final byFile = <String, List<DiagnosticIssueResult>>{};
    for (final d in deadNullAwareItems) {
      byFile.putIfAbsent(d.absolutePath, () => []).add(d);
    }

    final targetFiles =
        byFile.keys.map((p) => File(p)).where((f) => f.existsSync()).toList();
    BackupManifest? manifest;

    if (!dryRun && createBackup && targetFiles.isNotEmpty) {
      manifest = backupManager.createBackup(
        action: 'Simplify dead null-aware expressions',
        filesToBackup: targetFiles,
      );
    }

    final modified = <String>[];
    int cleanedCount = 0;

    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final items = entry.value;
      final file = File(filePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));
      items.sort((a, b) => b.line == a.line
          ? b.column.compareTo(a.column)
          : b.line.compareTo(a.line));

      for (final item in items) {
        final lineIdx = item.line - 1;
        if (lineIdx >= 0 && lineIdx < lines.length) {
          final line = lines[lineIdx];
          final colIdx = item.column - 1;
          if (colIdx >= 0 && colIdx < line.length) {
            // Find '?.' at or around colIdx
            final qIndex = line.indexOf('?.', colIdx > 1 ? colIdx - 1 : colIdx);
            if (qIndex != -1 && (qIndex - colIdx).abs() <= 3) {
              lines[lineIdx] =
                  '${line.substring(0, qIndex)}.${line.substring(qIndex + 2)}';
              cleanedCount++;
            }
          }
        }
      }

      if (!dryRun) {
        file.writeAsStringSync(lines.join('\n'));
      }
      modified.add(items.first.file);
    }

    return CleanResult(
      action: 'Clean Dead Null-Aware Expressions',
      success: true,
      modifiedFiles: modified,
      totalItemsCleaned: cleanedCount,
      backup: manifest,
    );
  }

  /// Surgically removes dangling import/export/part directives referencing missing or deleted files.
  List<RemovedDirectiveItem> cleanDanglingUriDirectives(
    List<HealthIssue> issues, {
    BackupManifest? backup,
  }) {
    final dangling = issues.where((i) => i.isDanglingUri).toList();
    if (dangling.isEmpty) {
      return [];
    }

    final byFile = <String, List<HealthIssue>>{};
    for (final issue in dangling) {
      byFile.putIfAbsent(issue.file, () => []).add(issue);
    }

    // Ensure all target files are backed up first
    if (backup != null) {
      final filesToBackup = byFile.keys
          .map((p) => resolveFile(p))
          .where((f) => f.existsSync())
          .toList();
      backupManager.appendToBackup(backup, filesToBackup);
    }

    final removedItems = <RemovedDirectiveItem>[];

    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final fileIssues = entry.value;
      final file = resolveFile(filePath);
      if (!file.existsSync()) {
        continue;
      }

      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));

      // Sort by line in descending order (bottom to top) to maintain stable indices
      fileIssues.sort((a, b) => b.line.compareTo(a.line));

      for (final issue in fileIssues) {
        final lineIdx = issue.line - 1;
        if (lineIdx < 0 || lineIdx >= lines.length) {
          continue;
        }

        // Find the start of the directive (import/export/part)
        int startIdx = lineIdx;
        while (startIdx > 0 &&
            !RegExp(r'^\s*(?:import|export|part)\b')
                .hasMatch(lines[startIdx])) {
          if (lineIdx - startIdx > 15) {
            break;
          }
          startIdx--;
        }

        if (!RegExp(r'^\s*(?:import|export|part)\b')
            .hasMatch(lines[startIdx])) {
          startIdx = lineIdx;
        }

        // Find the end of the directive (semicolon ';')
        int endIdx = startIdx;
        while (endIdx < lines.length && !lines[endIdx].contains(';')) {
          endIdx++;
          if (endIdx - startIdx > 30) {
            break;
          }
        }

        if (endIdx >= lines.length) {
          endIdx = startIdx;
        }

        final removedText =
            lines.sublist(startIdx, endIdx + 1).join('\n').trim();

        // Verify it contains import/export/part or the target URI
        final isDirective =
            RegExp(r'^(?:import|export|part)\b').hasMatch(removedText);
        final matchesUri =
            issue.uri != null && removedText.contains(issue.uri!);

        if (isDirective || matchesUri) {
          lines.removeRange(startIdx, endIdx + 1);

          // Clean duplicate empty lines if left
          if (startIdx < lines.length && lines[startIdx].trim().isEmpty) {
            if (startIdx > 0 && lines[startIdx - 1].trim().isEmpty) {
              lines.removeAt(startIdx);
            }
          }

          removedItems.add(RemovedDirectiveItem(
            file: getRelativePath(file.path, projectRoot.path),
            line: issue.line,
            directive: removedText.split('\n').first.trim(),
            targetUri: issue.uri ?? '',
          ));
        }
      }

      file.writeAsStringSync(lines.join('\n'));
    }

    return removedItems;
  }

  /// Runs post-cleanup Dart compilation/analyzer verification.
  ///
  /// Returns a [HealthCheckResult] containing detected compiler errors and warnings.
  HealthCheckResult verifyProjectHealth() {
    try {
      final result = Process.runSync(
        'dart',
        ['analyze', '--format=json'],
        workingDirectory: projectRoot.path,
        runInShell: true,
      );

      final stdoutStr = result.stdout as String? ?? '';
      if (stdoutStr.trim().isEmpty) {
        return HealthCheckResult();
      }

      final jsonStart = stdoutStr.indexOf('{');
      final jsonEnd = stdoutStr.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd < jsonStart) {
        return HealthCheckResult();
      }

      final jsonContent = stdoutStr.substring(jsonStart, jsonEnd + 1);
      final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
      final diagnostics = decoded['diagnostics'] as List<dynamic>? ?? [];

      final errors = <HealthIssue>[];
      final warnings = <HealthIssue>[];
      final uriRegex = RegExp(r"Target of URI doesn't exist:\s*'([^']+)'");

      for (final item in diagnostics) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final severity = (item['severity'] ?? '').toString().toUpperCase();
        final code = (item['code'] ?? '').toString();
        final msg = item['problemMessage']?.toString() ?? 'Error';
        final loc = item['location'] as Map<String, dynamic>?;
        final file = loc?['file']?.toString() ?? '';
        final normPath = file.replaceAll(r'\', '/').toLowerCase();
        if (normPath.contains('/.detect_unused') ||
            normPath.contains('/backups') ||
            normPath.contains('/.backups') ||
            normPath.endsWith('/backup') ||
            normPath.contains('/backup/')) {
          continue;
        }
        final line = (loc?['range']?['start']?['line'] as num?)?.toInt() ?? 1;
        final col = (loc?['range']?['start']?['column'] as num?)?.toInt() ?? 1;

        String? extractedUri;
        final match = uriRegex.firstMatch(msg);
        if (match != null) {
          extractedUri = match.group(1);
        }

        final issue = HealthIssue(
          severity: severity,
          code: code,
          message: msg,
          file: file,
          line: line,
          column: col,
          uri: extractedUri,
        );

        if (severity == 'ERROR') {
          errors.add(issue);
        } else if (severity == 'WARNING') {
          warnings.add(issue);
        }
      }
      return HealthCheckResult(errors: errors, warnings: warnings);
    } catch (e) {
      return HealthCheckResult(errors: [
        HealthIssue(
          severity: 'ERROR',
          code: 'verification_failed',
          message: 'Verification check failed to execute: $e',
          file: '',
          line: 1,
          column: 1,
        )
      ]);
    }
  }

  // --- Internal Helpers ---

  int _findDeclarationLine(List<String> lines, String name, int hintLine) {
    final pattern = RegExp(
      r'\b(?:(?:abstract\s+|base\s+|sealed\s+|interface\s+|final\s+)?class|(?:enum)|(?:mixin)|(?:extension\s+type)|(?:extension))\s+' +
          RegExp.escape(name) +
          r'\b',
    );

    final hintIdx = hintLine - 1;
    if (hintIdx >= 0 &&
        hintIdx < lines.length &&
        pattern.hasMatch(lines[hintIdx])) {
      return hintIdx;
    }

    // Search nearby
    for (int i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        return i;
      }
    }
    return -1;
  }

  int _findDeclarationEndLine(List<String> lines, int startLineIdx) {
    int depth = 0;
    bool foundOpenBrace = false;

    for (int i = startLineIdx; i < lines.length; i++) {
      final line = lines[i];

      // Handle semicolon declarations (e.g. class A = B with C;)
      if (!foundOpenBrace && line.contains(';')) {
        final openIdx = line.indexOf('{');
        final semiIdx = line.indexOf(';');
        if (openIdx == -1 || semiIdx < openIdx) {
          return i;
        }
      }

      for (int charIdx = 0; charIdx < line.length; charIdx++) {
        final char = line[charIdx];
        if (char == '{') {
          depth++;
          foundOpenBrace = true;
        } else if (char == '}') {
          depth--;
          if (foundOpenBrace && depth <= 0) {
            return i;
          }
        }
      }
    }

    return lines.length - 1;
  }
}
