import 'dart:convert';
import 'dart:io';

import 'auditor.dart';
import 'backup/backup_manager.dart';
import 'backup/backup_manifest.dart';
import 'cleaners/code_cleaner.dart';
import 'models.dart';
import 'utils.dart';
import 'version.dart';

/// Command-line interface runner for auditing and cleaning unused code.
class CliRunner {
  /// The list of raw command-line arguments passed to the runner.
  final List<String> args;

  /// Creates a new [CliRunner] with the provided command-line arguments.
  CliRunner(this.args);

  /// Executes the audit or cleanup based on the parsed CLI arguments.
  ///
  /// Returns exit code `0` on success or clean project, or `1` if issues or errors were found.
  int run() {
    if (args.contains('--help') || args.contains('-h')) {
      printHelp();
      return 0;
    }

    if (args.contains('--version') || args.contains('-V')) {
      printVersion();
      return 0;
    }

    final targetArg = extractTargetArg(args);
    Directory? startDir;
    if (targetArg != null) {
      try {
        final d = Directory(targetArg);
        if (d.existsSync()) {
          startDir = d;
        } else {
          final f = File(targetArg);
          if (f.existsSync()) {
            startDir = f.parent;
          }
        }
      } catch (_) {}
    }

    final projectRoot = findProjectOrWorkspaceRoot(startDir);

    // 1. Backups listing
    // 1. Backups listing
    if (args.contains('--backups') || args.contains('--list-backups')) {
      return _listBackups(projectRoot);
    }

    // Clean all backups to free disk space
    if (args.contains('--clean-backups') || args.contains('--delete-backups')) {
      final manager = BackupManager(projectRoot);
      final count = manager.deleteAllBackups();
      print(
          '🗑️ Cleaned $count backup snapshot(s) from .detect_unused/backups/.');
      return 0;
    }

    final keepBackup = args.contains('--keep-backup');
    final deleteAfterRestore = !keepBackup;

    // 2. Restore latest backup
    if (args.contains('--restore-latest')) {
      return _restoreLatest(projectRoot,
          deleteAfterRestore: deleteAfterRestore);
    }

    // 3. Restore specific backup by ID
    for (int i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--restore') {
        if (i + 1 < args.length) {
          final id = int.tryParse(args[i + 1]);
          if (id != null) {
            return _restoreBackup(projectRoot, id,
                deleteAfterRestore: deleteAfterRestore);
          }
        }
        print(
            '❌ Please specify a valid backup ID: detect_unused --restore <id>');
        return 1;
      } else if (a.startsWith('--restore=')) {
        final id = int.tryParse(a.substring('--restore='.length));
        if (id != null) {
          return _restoreBackup(projectRoot, id,
              deleteAfterRestore: deleteAfterRestore);
        }
        print(
            '❌ Please specify a valid backup ID: detect_unused --restore=<id>');
        return 1;
      }
    }

    // 4. Cleanup flags
    final cleanAll = args.contains('--clean-all') || args.contains('--clean');
    final cleanCommented = args.contains('--clean-commented-files') ||
        args.contains('--clean-commented');
    final cleanDeadBlocks = args.contains('--clean-dead-blocks');
    final cleanDeadClasses = args.contains('--clean-dead-classes');
    final privatizeInternal = args.contains('--privatize-internal');
    final cleanTodos =
        args.contains('--clean-todos') || args.contains('--clean-todo');
    final cleanUnusedImports = args.contains('--clean-unused-imports') ||
        args.contains('--clean-imports');
    final cleanDeadCode = args.contains('--clean-dead-code');

    final isCleaning = cleanAll ||
        cleanCommented ||
        cleanDeadBlocks ||
        cleanDeadClasses ||
        privatizeInternal ||
        cleanTodos ||
        cleanUnusedImports ||
        cleanDeadCode;

    final dryRun = args.contains('--dry-run');
    final isYes = args.contains('--yes') || args.contains('-y');
    final noBackup = args.contains('--no-backup');
    final verbose = args.contains('--verbose') || args.contains('-v');

    int commentThreshold = 60;
    final thresholdIdx = args.indexOf('--threshold');
    if (thresholdIdx != -1 && thresholdIdx + 1 < args.length) {
      final p = int.tryParse(args[thresholdIdx + 1]);
      if (p != null && p > 0 && p <= 100) {
        commentThreshold = p;
      }
    }

    int minBlockLines = 15;
    final minLinesIdx = args.indexOf('--min-lines');
    if (minLinesIdx != -1 && minLinesIdx + 1 < args.length) {
      final p = int.tryParse(args[minLinesIdx + 1]);
      if (p != null && p > 0) {
        minBlockLines = p;
      }
    }


    void updateProgress(int percent, String label) {
      final clamped = percent.clamp(0, 100);
      const barWidth = 28;
      final filled = ((clamped / 100) * barWidth).round();
      final empty = barWidth - filled;
      final bar = '${'█' * filled}${'░' * (empty > 0 ? empty : 0)}';
      final text =
          '\r⏳ Loading & Analyzing: [$bar] ${clamped.toString().padLeft(3)}% | $label';
      stdout.write(text);
    }

    if (isCleaning) {
      return _executeCleanup(
        projectRoot: projectRoot,
        targetArg: targetArg,
        commentThreshold: commentThreshold,
        minBlockLines: minBlockLines,
        verbose: verbose,
        cleanAll: cleanAll,
        cleanCommented: cleanCommented,
        cleanDeadBlocks: cleanDeadBlocks,
        cleanDeadClasses: cleanDeadClasses,
        privatizeInternal: privatizeInternal,
        cleanTodos: cleanTodos,
        cleanUnusedImports: cleanUnusedImports,
        cleanDeadCode: cleanDeadCode,
        dryRun: dryRun,
        isYes: isYes,
        noBackup: noBackup,
        onProgress: updateProgress,
      );
    }

    // Normal Audit Execution
    bool isJson = false;
    String jsonFileName = 'detect_unused_code.json';

    for (int i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--json') {
        isJson = true;
        if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          final next = args[i + 1].trim();
          if (next.endsWith('.json')) {
            jsonFileName = next;
          }
        }
      } else if (a.startsWith('--json=')) {
        isJson = true;
        final val = a.substring('--json='.length).trim();
        if (val.isNotEmpty) {
          jsonFileName = val.endsWith('.json') ? val : '$val.json';
        }
      }
    }

    final onlyUnusedClasses =
        args.contains('--unused-classes') || args.contains('--classes');
    final onlyCommented = args.contains('--commented') ||
        args.contains('--commented-code') ||
        args.contains('--comments');
    final onlyTodos =
        args.contains('--todos-only') || args.contains('--todo-only');
    final onlyDiagnostics =
        args.contains('--diagnostics-only') || args.contains('--analyzer-only');

    final noTodos = args.contains('--no-todos') || args.contains('--no-todo');
    final noDiagnostics =
        args.contains('--no-diagnostics') || args.contains('--no-analyzer');
    final noInternal = args.contains('--no-internal');
    final includeInternal = !noInternal;

    final runClassAnalysis = onlyTodos || onlyDiagnostics
        ? false
        : (onlyUnusedClasses ? true : !onlyCommented);
    final runCommentAnalysis = onlyTodos || onlyDiagnostics
        ? false
        : (onlyCommented ? true : !onlyUnusedClasses);
    final runTodoAnalysis = onlyTodos
        ? true
        : (!noTodos &&
            !onlyUnusedClasses &&
            !onlyCommented &&
            !onlyDiagnostics);
    final runDiagnostics = onlyDiagnostics
        ? true
        : (!noDiagnostics &&
            !onlyUnusedClasses &&
            !onlyCommented &&
            !onlyTodos);

    final options = AuditorOptions(
      targetPath: targetArg,
      runClassAnalysis: runClassAnalysis,
      runCommentAnalysis: runCommentAnalysis,
      includeInternal: includeInternal,
      runTodoAnalysis: runTodoAnalysis,
      runDiagnostics: runDiagnostics,
      commentThreshold: commentThreshold,
      minBlockLines: minBlockLines,
      verbose: verbose,
    );

    final auditor = UnusedCodeAuditor(
      projectRoot: projectRoot,
      options: options,
    );

    final report = auditor.run(onProgress: updateProgress);
    stdout.writeln('\n');

    final bool hasIssues = report.deadClasses.isNotEmpty ||
        report.fullyCommentedFiles.isNotEmpty ||
        report.diagnostics.isNotEmpty;

    if (isJson) {
      final jsonMap = report.toJson(includeInternal: includeInternal);
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);

      final outputFile = File('${Directory.current.path}/$jsonFileName');
      outputFile.writeAsStringSync(jsonString);

      print(
          '================================================================================');
      print('✅ JSON Audit Report generated successfully!');
      print('📁 File Saved: [${outputFile.path}]');
      print('📄 Dart Files Scanned:       ${report.totalTargetDartFiles}');
      print('💀 Dead Classes Found:       ${report.deadClasses.length}');
      if (includeInternal) {
        print(
            '⚠️ Internal-only Classes:    ${report.internalOnlyClasses.length}');
      }
      print(
          '🚫 Fully Commented Files:    ${report.fullyCommentedFiles.length}');
      print(
          '📦 Files with Dead Blocks:   ${report.filesWithCommentBlocks.length}');
      print('📝 TODO Tasks Found:         ${report.todos.length}');
      print('📦 Unused Imports:           ${report.unusedImports.length}');
      print(
          '🏷️ Unused Variables/Fields:   ${report.unusedVariablesAndFields.length}');
      print('⚙️ Unused Elements:          ${report.unusedElements.length}');
      print(
          '💀 Dead Code & Null-aware:   ${report.deadCodeAndExpressions.length}');
      print(
          '================================================================================\n');

      return hasIssues ? 1 : 0;
    }

    _printConsoleReport(report, options, projectRoot);

    return hasIssues ? 1 : 0;
  }

  int _listBackups(Directory projectRoot) {
    final manager = BackupManager(projectRoot);
    final backups = manager.listBackups();
    if (backups.isEmpty) {
      print(
          '================================================================================');
      print('📦 No backups found in .detect_unused/backups/.');
      print(
          '================================================================================');
      return 0;
    }
    print(
        '================================================================================');
    print(
        '📦 DETECT_UNUSED_CODE: SNAPSHOT BACKUPS (${backups.length} available)');
    print(
        '================================================================================');
    for (final b in backups) {
      print('  ID: #${b.id.toString().padRight(4)} | ${b.formattedDate}');
      print('  Action:        ${b.action}');
      print(
          '  Files Stored:  ${b.files.length} (${b.files.where((f) => f.isDeleted).length} deleted, ${b.files.where((f) => !f.isDeleted).length} modified)');
      print('  Snapshot Dir:  ${b.backupDirName}');
      print('  To restore:    detect_unused --restore ${b.id}');
      print(
          '--------------------------------------------------------------------------------');
    }
    return 0;
  }

  int _restoreLatest(
    Directory projectRoot, {
    bool deleteAfterRestore = true,
  }) {
    final manager = BackupManager(projectRoot);
    final latest = manager.getLatestBackup();
    if (latest == null) {
      print('❌ No backups found to restore in .detect_unused/backups/.');
      return 1;
    }
    return _restoreBackup(projectRoot, latest.id,
        deleteAfterRestore: deleteAfterRestore);
  }

  int _restoreBackup(
    Directory projectRoot,
    int id, {
    bool deleteAfterRestore = true,
  }) {
    final manager = BackupManager(projectRoot);
    final manifest = manager.getBackup(id);
    if (manifest == null) {
      print(
          '❌ Backup #$id not found. Use "detect_unused --backups" to view all available backups.');
      return 1;
    }

    stdout.write(
        '⚠️ Restore backup #$id ("${manifest.action}")? This will overwrite active project files. [y/N]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input != 'y' && input != 'yes') {
      print('❌ Restore cancelled by user.');
      return 0;
    }

    final result =
        manager.restoreBackup(id, deleteAfterRestore: deleteAfterRestore);
    if (result.success) {
      print(
          '\n================================================================================');
      print('🔄 RESTORE COMPLETED SUCCESSFULLY (Backup #$id)');
      print(
          '================================================================================');
      print('  ✅ Files Restored/Recreated: ${result.restoredFiles.length}');
      print(
          '  📁 Project state has been restored to: ${manifest.formattedDate}');
      if (result.snapshotDeleted) {
        print(
            '  🗑️ Backup #$id snapshot folder was removed to free up disk space.');
      }
      print(
          '================================================================================');
      return 0;
    } else {
      print('❌ Restore failed: ${result.message}');
      return 1;
    }
  }

  int _executeCleanup({
    required Directory projectRoot,
    required String? targetArg,
    required int commentThreshold,
    required int minBlockLines,
    required bool verbose,
    required bool cleanAll,
    required bool cleanCommented,
    required bool cleanDeadBlocks,
    required bool cleanDeadClasses,
    required bool privatizeInternal,
    required bool cleanTodos,
    required bool cleanUnusedImports,
    required bool cleanDeadCode,
    required bool dryRun,
    required bool isYes,
    required bool noBackup,
    required AuditorProgressCallback onProgress,
  }) {
    final auditor = UnusedCodeAuditor(
      projectRoot: projectRoot,
      options: AuditorOptions(
        targetPath: targetArg,
        runClassAnalysis: cleanAll || cleanDeadClasses || privatizeInternal,
        runCommentAnalysis: cleanAll || cleanCommented || cleanDeadBlocks,
        includeInternal: cleanAll || privatizeInternal,
        runTodoAnalysis: cleanAll || cleanTodos,
        runDiagnostics: cleanAll || cleanUnusedImports || cleanDeadCode,
        commentThreshold: commentThreshold,
        minBlockLines: minBlockLines,
        verbose: verbose,
      ),
    );

    final report = auditor.run(onProgress: onProgress);
    stdout.writeln('\n');

    final filesToDelete = (cleanAll || cleanCommented)
        ? report.fullyCommentedFiles
        : <CommentedFileResult>[];
    final blocksToClean = (cleanAll || cleanDeadBlocks)
        ? report.filesWithCommentBlocks
        : <CommentedFileResult>[];
    final deadClassesToClean = (cleanAll || cleanDeadClasses)
        ? report.deadClasses
        : <UnusedClassResult>[];
    final internalClassesToClean = (cleanAll || privatizeInternal)
        ? report.internalOnlyClasses
        : <UnusedClassResult>[];
    final todosToClean =
        (cleanAll || cleanTodos) ? report.todos : <TodoItemResult>[];
    final importsToClean = (cleanAll || cleanUnusedImports)
        ? report.unusedImports
        : <DiagnosticIssueResult>[];
    final deadCodeToClean = (cleanAll || cleanDeadCode)
        ? report.deadCodeAndExpressions
        : <DiagnosticIssueResult>[];

    final totalTargets = filesToDelete.length +
        blocksToClean.length +
        deadClassesToClean.length +
        internalClassesToClean.length +
        todosToClean.length +
        importsToClean.length +
        deadCodeToClean.length;

    if (totalTargets == 0) {
      print(
          '================================================================================');
      print(
          '✨ CLEANUP SUMMARY: Nothing to clean! All code is active and in top shape.');
      print(
          '================================================================================');
      return 0;
    }

    print(
        '================================================================================');
    print('🧹 DETECT_UNUSED_CODE: PLANNED REMEDIATION');
    print(
        '================================================================================');
    if (filesToDelete.isNotEmpty) {
      print('  🗑️ Fully Commented Files to Delete (${filesToDelete.length}):');
      for (final f in filesToDelete) {
        print('     - ${f.file}');
      }
    }
    if (blocksToClean.isNotEmpty) {
      final totalBlocks =
          blocksToClean.fold<int>(0, (sum, f) => sum + f.blocks.length);
      print(
          '  ✂️ Dead Comment Blocks to Remove ($totalBlocks blocks in ${blocksToClean.length} files):');
      for (final f in blocksToClean) {
        print('     - ${f.file} (${f.blocks.length} block(s))');
      }
    }
    if (deadClassesToClean.isNotEmpty) {
      print('  💀 Dead Classes to Remove (${deadClassesToClean.length}):');
      for (final c in deadClassesToClean) {
        print('     - ${c.name} in ${c.relPath}');
      }
    }
    if (internalClassesToClean.isNotEmpty) {
      print(
          '  🔒 File-Internal Classes to Privatize (${internalClassesToClean.length}):');
      for (final c in internalClassesToClean) {
        print('     - ${c.name} -> _${c.name} in ${c.relPath}');
      }
    }
    if (todosToClean.isNotEmpty) {
      print('  📝 TODO Comments to Clean (${todosToClean.length}):');
      for (final t in todosToClean.take(10)) {
        print('     - ${t.file}:${t.line} - ${t.message}');
      }
      if (todosToClean.length > 10) {
        print('     ... and ${todosToClean.length - 10} more');
      }
    }
    if (importsToClean.isNotEmpty) {
      print(
          '  📦 Unused & Unnecessary Imports to Remove (${importsToClean.length}):');
      for (final i in importsToClean) {
        print('     - ${i.file}:${i.line} (${i.message})');
      }
    }
    if (deadCodeToClean.isNotEmpty) {
      print(
          '  ⚡ Dead Code & Expressions to Remediate (${deadCodeToClean.length}):');
      for (final d in deadCodeToClean) {
        print('     - ${d.file}:${d.line} (${d.message})');
      }
    }
    print(
        '--------------------------------------------------------------------------------');

    if (dryRun) {
      print(
          '🔍 [DRY-RUN]: Simulation complete. No files on disk were modified.');
      print(
          'ℹ️ In active execution, detect_unused will execute cleanup step-by-step,');
      print(
          '   re-auditing between each category to ensure exact AST line integrity.');
      return 0;
    }

    if (!isYes) {
      stdout.write(
          '⚠️ Are you sure you want to proceed with this step-by-step cleanup? [y/N]: ');
      final input = stdin.readLineSync()?.trim().toLowerCase();
      if (input != 'y' && input != 'yes') {
        print('❌ Cleanup aborted by user. No files were modified.');
        return 0;
      }
    }

    final cleaner = CodeCleaner(projectRoot);

    final stages = <_CleanupStage>[];

    if (cleanAll || cleanCommented) {
      stages.add(_CleanupStage(
        id: 'commented_files',
        title: 'Fully Commented Files',
        emoji: '🗑️',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runCommentAnalysis: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.fullyCommentedFiles.isNotEmpty,
        targetsCount: (report) => report.fullyCommentedFiles.length,
        getTargetFilesToBackup: (report, cleaner) => report.fullyCommentedFiles
            .map((f) => cleaner.resolveFile(f.absolutePath))
            .where((f) => f.existsSync())
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => report
            .fullyCommentedFiles
            .map((f) => cleaner.resolveFile(f.absolutePath).path)
            .toList(),
        execute: (report, cleaner) => cleaner.cleanCommentedFiles(
          report.fullyCommentedFiles,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    if (cleanAll || cleanDeadClasses) {
      stages.add(_CleanupStage(
        id: 'dead_classes',
        title: 'Dead Classes & Widgets',
        emoji: '💀',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runClassAnalysis: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.deadClasses.isNotEmpty,
        targetsCount: (report) => report.deadClasses.length,
        getTargetFilesToBackup: (report, cleaner) => report.deadClasses
            .map((c) => cleaner.resolveFile(c.file))
            .where((f) => f.existsSync())
            .toSet()
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => const <String>[],
        execute: (report, cleaner) => cleaner.cleanDeadClasses(
          report.deadClasses,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    if (cleanAll || cleanDeadBlocks) {
      stages.add(_CleanupStage(
        id: 'dead_blocks',
        title: 'Dead Comment Blocks',
        emoji: '✂️',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runCommentAnalysis: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.filesWithCommentBlocks.isNotEmpty,
        targetsCount: (report) => report.filesWithCommentBlocks
            .fold<int>(0, (sum, f) => sum + f.blocks.length),
        getTargetFilesToBackup: (report, cleaner) => report
            .filesWithCommentBlocks
            .map((b) => cleaner.resolveFile(b.absolutePath))
            .where((f) => f.existsSync())
            .toSet()
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => const <String>[],
        execute: (report, cleaner) => cleaner.cleanDeadBlocks(
          report.filesWithCommentBlocks,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    if (cleanAll || privatizeInternal) {
      stages.add(_CleanupStage(
        id: 'privatize_internal',
        title: 'File-Internal Classes (Privatization)',
        emoji: '🔒',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runClassAnalysis: true,
            includeInternal: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.internalOnlyClasses.isNotEmpty,
        targetsCount: (report) => report.internalOnlyClasses.length,
        getTargetFilesToBackup: (report, cleaner) => report.internalOnlyClasses
            .map((c) => cleaner.resolveFile(c.file))
            .where((f) => f.existsSync())
            .toSet()
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => const <String>[],
        execute: (report, cleaner) => cleaner.privatizeInternalClasses(
          report.internalOnlyClasses,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    if (cleanAll || cleanDeadCode) {
      stages.add(_CleanupStage(
        id: 'dead_code',
        title: 'Dead Code & Null-Aware Expressions',
        emoji: '⚡',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runDiagnostics: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.deadCodeAndExpressions.isNotEmpty,
        targetsCount: (report) => report.deadCodeAndExpressions.length,
        getTargetFilesToBackup: (report, cleaner) => report
            .deadCodeAndExpressions
            .map((d) => cleaner.resolveFile(d.absolutePath))
            .where((f) => f.existsSync())
            .toSet()
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => const <String>[],
        execute: (report, cleaner) => cleaner.cleanDeadNullAware(
          report.deadCodeAndExpressions,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    if (cleanAll || cleanTodos) {
      stages.add(_CleanupStage(
        id: 'todos',
        title: 'TODO Comments',
        emoji: '📝',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runTodoAnalysis: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.todos.isNotEmpty,
        targetsCount: (report) => report.todos.length,
        getTargetFilesToBackup: (report, cleaner) => report.todos
            .map((t) => cleaner.resolveFile(t.absolutePath))
            .where((f) => f.existsSync())
            .toSet()
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => const <String>[],
        execute: (report, cleaner) => cleaner.cleanTodos(
          report.todos,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    if (cleanAll || cleanUnusedImports) {
      stages.add(_CleanupStage(
        id: 'unused_imports',
        title: 'Unused Imports',
        emoji: '📦',
        createAuditor: () => UnusedCodeAuditor(
          projectRoot: projectRoot,
          options: AuditorOptions(
            targetPath: targetArg,
            runDiagnostics: true,
            commentThreshold: commentThreshold,
            minBlockLines: minBlockLines,
            verbose: verbose,
          ),
        ),
        hasTargets: (report) => report.unusedImports.isNotEmpty,
        targetsCount: (report) => report.unusedImports.length,
        getTargetFilesToBackup: (report, cleaner) => report.unusedImports
            .map((d) => cleaner.resolveFile(d.absolutePath))
            .where((f) => f.existsSync())
            .toSet()
            .toList(),
        getFilesMarkedForDeletion: (report, cleaner) => const <String>[],
        execute: (report, cleaner) => cleaner.cleanUnusedImports(
          report.unusedImports,
          dryRun: false,
          createBackup: false,
        ),
      ));
    }

    final totalStages = stages.length;
    final allDeletedFiles = <String>{};
    final allModifiedFiles = <String>{};
    int totalRemediated = 0;
    BackupManifest? sharedBackup;

    print(
        '\n================================================================================');
    print('🚀 STARTING STEP-BY-STEP STAGED REMEDIATION ($totalStages Stages)');
    print(
        '================================================================================');

    for (int i = 0; i < totalStages; i++) {
      final stage = stages[i];
      final stepNum = i + 1;

      print(
          '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print(
          '▶ [Step $stepNum/$totalStages] ${stage.emoji} Auditing & Remediating: ${stage.title}');
      print(
          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      void stepProgress(int percent, String label) {
        final clamped = percent.clamp(0, 100);
        const barWidth = 24;
        final filled = ((clamped / 100) * barWidth).round();
        final empty = barWidth - filled;
        final bar = '${'█' * filled}${'░' * (empty > 0 ? empty : 0)}';
        final text =
            '\r⏳ [Step $stepNum/$totalStages] [$bar] ${clamped.toString().padLeft(3)}% | $label';
        stdout.write(text);
      }

      final stageAuditor = stage.createAuditor();
      final stageReport = stageAuditor.run(onProgress: stepProgress);
      stdout.writeln('\n');

      if (!stage.hasTargets(stageReport)) {
        print(
            '  ✨ No ${stage.title.toLowerCase()} found in active code. Skipping.');
        continue;
      }

      final count = stage.targetsCount(stageReport);
      print('  🎯 Found $count item(s) to remediate in ${stage.title}.');

      if (!noBackup) {
        final filesToBackup =
            stage.getTargetFilesToBackup(stageReport, cleaner);
        final filesToDelete =
            stage.getFilesMarkedForDeletion(stageReport, cleaner);

        if (filesToBackup.isNotEmpty) {
          if (sharedBackup == null) {
            sharedBackup = cleaner.backupManager.createBackup(
              action: 'Clean unused code (step $stepNum: ${stage.title})',
              filesToBackup: filesToBackup,
              filesMarkedForDeletion: filesToDelete,
            );
          } else {
            cleaner.backupManager.appendToBackup(
              sharedBackup,
              filesToBackup,
              filesMarkedForDeletion: filesToDelete,
            );
          }
        }
      }

      final res = stage.execute(stageReport, cleaner);
      allDeletedFiles.addAll(res.deletedFiles);
      allModifiedFiles.addAll(res.modifiedFiles);
      totalRemediated += res.totalItemsCleaned;

      print(
          '  ✅ [Step $stepNum/$totalStages] Successfully remediated ${res.totalItemsCleaned} item(s).');

      // Auto-resolve dangling URI directives immediately if any files were deleted in this stage
      if (res.deletedFiles.isNotEmpty) {
        final danglingCheck = cleaner.verifyProjectHealth();
        if (danglingCheck.hasDanglingUris) {
          final removed = cleaner.cleanDanglingUriDirectives(
            danglingCheck.errors,
            backup: sharedBackup,
          );
          if (removed.isNotEmpty) {
            print(
                '  ✂️ Auto-removed ${removed.length} dangling import/export directive(s) after file deletion.');
          }
        }
      }
    }

    print(
        '\n================================================================================');
    print('🎉 STEP-BY-STEP CLEANUP COMPLETED');
    print(
        '================================================================================');
    print('  ✅ Files Deleted:    ${allDeletedFiles.length}');
    print('  ✏️ Files Modified:   ${allModifiedFiles.length}');
    print('  🎯 Items Remediated: $totalRemediated');
    if (sharedBackup != null) {
      print(
          '  📦 Backup Snapshot:  #${sharedBackup.id} (${sharedBackup.backupDirName})');
      print(
          '     Restore command:  detect_unused --restore ${sharedBackup.id}');
    }
    print(
        '--------------------------------------------------------------------------------');

    stdout.write('🔍 Verifying final project compilation and analyzer health...');
    var health = cleaner.verifyProjectHealth();

    // Auto-resolve dangling imports/exports referencing deleted files
    if (health.hasDanglingUris) {
      stdout.writeln(' ⚠️ Dangling references detected!\n');
      print(
          '================================================================================');
      print('🧹 AUTO-RESOLVING DANGLING EXPORTS & IMPORTS');
      print(
          '================================================================================');
      print('⚠️ Detected export/import directives referencing deleted files:');
      for (final issue in health.errors.where((e) => e.isDanglingUri)) {
        final relFile = getRelativePath(issue.file, projectRoot.path);
        print(
            '   ⚠️ [L${issue.line.toString().padRight(4)}] $relFile ➜ ${issue.message}');
      }

      print(
          '\n⚙️ Automatically removing dangling directives from barrel & source files...');
      final removed = cleaner.cleanDanglingUriDirectives(
        health.errors,
        backup: sharedBackup,
      );

      for (final item in removed) {
        print(
            '   ✂️ [L${item.line.toString().padRight(4)}] ${item.file} ➜ Removed: ${item.directive}');
      }
      print('✅ Successfully removed ${removed.length} dangling directive(s).');
      print(
          '--------------------------------------------------------------------------------');

      // Re-verify compilation health after auto-fixing dangling directives
      stdout
          .write('🔍 Re-verifying project compilation and analyzer health...');
      health = cleaner.verifyProjectHealth();
    }

    if (health.hasErrors) {
      stdout.writeln(' ❌ Issues detected!\n');
      print('⚠️ [WARNING] Compiler errors detected after cleanup:');
      for (final err in health.errors) {
        print('  - ${err.file}:${err.line} - ${err.message}');
      }
      if (sharedBackup != null) {
        stdout.write(
            '\n⚠️ Would you like to automatically rollback to Backup #${sharedBackup.id}? [Y/n]: ');
        final rbInput = stdin.readLineSync()?.trim().toLowerCase();
        if (rbInput == null ||
            rbInput.isEmpty ||
            rbInput == 'y' ||
            rbInput == 'yes') {
          final rb = cleaner.backupManager.restoreBackup(
            sharedBackup.id,
            deleteAfterRestore: true,
          );
          if (rb.success) {
            print('🔄 Project successfully restored to pre-cleanup state!');
            if (rb.snapshotDeleted) {
              print(
                  '  🗑️ Backup #${sharedBackup.id} folder was removed to free up disk space.');
            }
          } else {
            print('❌ Restore failed: ${rb.message}');
          }
          return 1;
        }
      }
    } else {
      stdout.writeln(' ✅ Healthy (0 compiler errors)! All clean!');
    }

    return 0;
  }

  void _printConsoleReport(
    AnalysisReport report,
    AuditorOptions options,
    Directory projectRoot,
  ) {
    print('\n${'=' * 78}');
    print('🔎 DEAD CODE & COMPREHENSIVE CODE AUDITOR REPORT');
    print('📁 Target Scope: [${report.targetPath}]');
    print(
        '📄 Dart Files:   ${report.totalTargetDartFiles} scanned (out of ${report.totalProjectDartFiles} total in project)');
    print('=' * 78);

    if (options.runCommentAnalysis) {
      if (report.fullyCommentedFiles.isNotEmpty) {
        print(
            '\n🚫 【1. Fully Commented-Out Files (100% Comments)】 - (${report.fullyCommentedFiles.length} files):');
        print(
            '   (These files contain entirely commented-out code and can be safely deleted or restored)');
        for (final f in report.fullyCommentedFiles) {
          final classesHint = f.commentedClasses.isNotEmpty
              ? '\n      ↳ Commented classes found inside: [ ${f.commentedClasses.join(', ')} ]'
              : '';
          print(
              '   🗑️  ${f.fileUri}  [${f.commentRatio}% Comments - ${f.totalNonEmptyLines} lines]$classesHint');
        }
      } else {
        print(
            '\n✅ Commented Code: No commented-out files or dead code blocks detected in this scope.');
      }

      if (report.highRatioFiles.isNotEmpty) {
        print(
            '\n⚠️ 【2. Heavily Commented Files (>= ${options.commentThreshold}%)】 - (${report.highRatioFiles.length} files):');
        for (final f in report.highRatioFiles) {
          print(
              '   📄 ${f.fileUri}  ➜ ${f.commentRatio}% comments (${f.commentLinesCount}/${f.totalNonEmptyLines} lines)');
        }
      }

      if (report.filesWithCommentBlocks.isNotEmpty) {
        final totalBlocks = report.filesWithCommentBlocks
            .fold<int>(0, (sum, f) => sum + f.blocks.length);
        print(
            '\n📦 【3. Active Files Containing Dead Code Blocks】 - ($totalBlocks blocks in ${report.filesWithCommentBlocks.length} files):');
        for (final f in report.filesWithCommentBlocks) {
          print(
              '   📁 ${f.fileUri} (${f.blocks.length} block${f.blocks.length > 1 ? 's' : ''}):');
          for (final b in f.blocks) {
            print(
                '      ↳ Lines ${b.startLine.toString().padRight(4)} - ${b.endLine.toString().padRight(4)} (${b.totalLines} lines, ~${b.codeLines} lines of commented code)');
            if (options.verbose) {
              final snippet =
                  b.sample.split('\n').map((l) => '         | $l').join('\n');
              print(snippet);
            }
          }
        }
      }
    }

    print('\n${'-' * 78}');

    if (options.runClassAnalysis) {
      if (report.deadClasses.isNotEmpty) {
        print(
            '\n💀 【4. Dead Classes / Elements (Zero Usages Across Entire Project)】 - (${report.deadClasses.length} items):');
        for (final c in report.deadClasses) {
          final typeBadge = c.isPrivate ? 'PRIVATE' : 'PUBLIC';
          final lineFormatted = '[L${c.line.toString().padRight(4)}]';
          print(
              '   ❌ $lineFormatted ${c.fileUri} ➜ ${c.name} ($typeBadge ${c.category})');
        }
      } else {
        print(
            '\n✅ Unused Classes: All classes in this scope are actively used across the project.');
      }

      if (options.includeInternal) {
        if (report.internalOnlyClasses.isNotEmpty) {
          print(
              '\n⚠️ 【5. File-Internal Only Classes (Zero External References)】 - (${report.internalOnlyClasses.length} items):');
          print(
              '   (These classes are declared as public but only used inside their declaring file)');
          for (final c in report.internalOnlyClasses) {
            final lineFormatted = '[L${c.line.toString().padRight(4)}]';
            print(
                '   🔍 $lineFormatted ${c.fileUri} ➜ ${c.name} (${c.category}, ${c.internalMatches} local usages) ➜ Consider making private (_${c.name})');
          }
        } else {
          print(
              '\n✅ Internal Classes: All public classes are shared or no file-internal only classes.');
        }
      }
    }

    if (options.runTodoAnalysis) {
      print('\n${'-' * 78}');
      if (report.todos.isNotEmpty) {
        print(
            '\n📝 【6. TODO Comments & Pending Tasks】 - (${report.todos.length} items):');
        for (final t in report.todos) {
          final lineFormatted = '[L${t.line.toString().padRight(4)}]';
          print('   📝 $lineFormatted ${t.fileUri} ➜ ${t.message}');
        }
      } else {
        print('\n✅ TODO Tasks: No pending TODO comments found in this scope.');
      }
    }

    if (options.runDiagnostics) {
      print('\n${'-' * 78}');

      if (report.unusedImports.isNotEmpty) {
        print(
            '\n📦 【7. Unused & Unnecessary Imports】 - (${report.unusedImports.length} items):');
        for (final d in report.unusedImports) {
          final lineFormatted = '[L${d.line.toString().padRight(4)}]';
          print('   📦 $lineFormatted ${d.fileUri} ➜ ${d.message}');
        }
      } else {
        print('\n✅ Imports: No unused or unnecessary imports detected.');
      }

      if (report.unusedVariablesAndFields.isNotEmpty) {
        print(
            '\n🏷️ 【8. Unused Local Variables & Fields】 - (${report.unusedVariablesAndFields.length} items):');
        for (final d in report.unusedVariablesAndFields) {
          final lineFormatted = '[L${d.line.toString().padRight(4)}]';
          print('   🏷️ $lineFormatted ${d.fileUri} ➜ ${d.message}');
        }
      } else {
        print(
            '\n✅ Variables & Fields: No unused local variables or fields detected.');
      }

      if (report.unusedElements.isNotEmpty) {
        print(
            '\n⚙️ 【9. Unused Elements & Private Members】 - (${report.unusedElements.length} items):');
        for (final d in report.unusedElements) {
          final lineFormatted = '[L${d.line.toString().padRight(4)}]';
          print('   ⚙️ $lineFormatted ${d.fileUri} ➜ ${d.message}');
        }
      } else {
        print(
            '\n✅ Elements: No unused private methods, functions, or elements detected.');
      }

      if (report.deadCodeAndExpressions.isNotEmpty) {
        print(
            '\n💀 【10. Dead Code & Dead Null-Aware Expressions】 - (${report.deadCodeAndExpressions.length} items):');
        for (final d in report.deadCodeAndExpressions) {
          final lineFormatted = '[L${d.line.toString().padRight(4)}]';
          print('   💀 $lineFormatted ${d.fileUri} ➜ ${d.message}');
        }
      } else {
        print(
            '\n✅ Dead Code: No unreachable dead code or dead null-aware expressions detected.');
      }
    }

    print('\n${'=' * 78}');
    print('📊 AUDIT SUMMARY:');
    print('   Target Path:               ${report.targetPath}');
    print('   Dart Files Analyzed:       ${report.totalTargetDartFiles}');
    print('   Dead Classes Found:        ${report.deadClasses.length}');
    if (options.includeInternal) {
      print(
          '   Internal-only Classes:     ${report.internalOnlyClasses.length}');
    }
    print('   Fully Commented Files:     ${report.fullyCommentedFiles.length}');
    print(
        '   Files with Dead Blocks:    ${report.filesWithCommentBlocks.length}');
    print('   TODO Tasks Found:          ${report.todos.length}');
    print('   Unused Imports:            ${report.unusedImports.length}');
    print(
        '   Unused Variables/Fields:   ${report.unusedVariablesAndFields.length}');
    print('   Unused Elements:           ${report.unusedElements.length}');
    print(
        '   Dead Code & Null-Aware:    ${report.deadCodeAndExpressions.length}');
    print('=' * 78);
    print('💡 Pro-tips & Automated Remediation:');
    print('   • Preview cleanup without modifying files on disk (simulation):');
    print('     ↳ detect_unused --clean-all --dry-run');
    print(
        '   • Safely clean all detected issues (auto-backup + confirmation):');
    print('     ↳ detect_unused --clean-all');
    print('   • Clean specific categories:');
    print(
        '     ↳ detect_unused --clean-commented-files   (Delete 100% commented-out files)');
    print(
        '     ↳ detect_unused --clean-dead-blocks       (Remove dead code blocks)');
    print(
        '     ↳ detect_unused --clean-dead-classes      (Remove zero-usage dead classes)');
    print(
        '     ↳ detect_unused --privatize-internal      (Privatize internal-only classes to _)');
    print(
        '     ↳ detect_unused --clean-todos             (Strip/clean pending TODO comments)');
    print(
        '     ↳ detect_unused --clean-unused-imports    (Remove unused & unnecessary imports)');
    print(
        '     ↳ detect_unused --clean-dead-code         (Clean dead null-aware ?. and dead code)');
    print('   • Snapshot backups & rollback:');
    print(
        '     ↳ detect_unused --backups                 (List all available backups)');
    print(
        '     ↳ detect_unused --restore <id>            (Restore project to specific backup)');
    print(
        '     ↳ detect_unused --restore-latest          (Restore to most recent snapshot)');
    print('   • View full reference and options:');
    print('     ↳ detect_unused --help');
    print('${'=' * 78}\n');
  }

  /// Extracts target path argument from the command-line options.
  static String? extractTargetArg(List<String> args) {
    String cleanInputPath(String raw) {
      var s = raw.trim();
      if ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'"))) {
        s = s.substring(1, s.length - 1).trim();
      }
      return s;
    }

    for (int i = 0; i < args.length; i++) {
      final a = args[i];
      final match = RegExp(r'^--(?:url|path|target)=(.*)$').firstMatch(a);
      if (match != null) {
        final raw = match.group(1)!;
        final val = cleanInputPath(raw);
        if (val.isNotEmpty) {
          return val;
        }
        if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          return cleanInputPath(args[i + 1]);
        }
      }
      if (RegExp(r'^--(?:url|path|target)$').hasMatch(a)) {
        if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          return cleanInputPath(args[i + 1]);
        }
      }
    }

    for (int i = 0; i < args.length; i++) {
      final a = args[i];
      if (a.startsWith('-')) {
        continue;
      }
      if (i > 0 &&
          (args[i - 1] == '--threshold' ||
              args[i - 1] == '--min-lines' ||
              args[i - 1] == '--json' ||
              args[i - 1] == '--restore')) {
        continue;
      }
      return cleanInputPath(a);
    }
    return null;
  }

  /// Prints the command-line usage and options reference.
  static void printHelp() {
    print('''
================================================================================
  detect_unused_code
  A fast, zero-dependency Dart & Flutter dead code auditor and remediation engine.
================================================================================

USAGE:
  detect_unused [OPTIONS]
  detect_unused_code [OPTIONS]
  dart run detect_unused_code [OPTIONS]
  dart run detect_unused_code:detect_unused [OPTIONS]

DEFAULT BEHAVIOR:
  Running `detect_unused_code` without options automatically executes ALL 13 checks:
    1. Fully commented-out files (100% comments)
    2. Heavily commented files (>= threshold)
    3. Active files containing dead code blocks
    4. Dead classes, mixins, enums (Zero usages project-wide)
    5. File-internal only public classes (0 external references)
    6. TODO comments & pending tasks (// TODO: ...)
    7. Unused imports (unused_import)
    8. Unnecessary imports (unnecessary_import)
    9. Unused local variables (unused_local_variable)
   10. Unused fields (unused_field)
   11. Unused private elements & functions (unused_element)
   12. Dead code unreachable blocks (dead_code)
   13. Dead null-aware expressions (dead_null_aware_expression)

TARGET SPECIFICATION:
  --url=<path>             Target directory or specific Dart file to scan.
                           Can also be written as: --url "path" or as a positional argument.
                           Accepts relative or absolute paths (e.g. "lib/features/auth").
                           Default: Scans the entire project if omitted.
  --path=<path>            Aliases for --url.
  --target=<path>

AUTOMATED REMEDIATION & CLEANUP:
  --clean-all, --clean     Remediate all detected safe issues in one cohesive pass:
                           deletes 100% commented files, removes dead code blocks, removes
                           dead classes, privatizes internal classes, strips TODOs, and
                           removes unused imports with an automatic snapshot backup.
  --clean-commented-files  Permanently delete fully commented-out files (>=90% comments).
  --clean-dead-blocks      Surgically remove large blocks of commented-out code in active files.
  --clean-dead-classes     Remove zero-usage dead classes, mixins, and widgets.
  --privatize-internal     Convert file-internal public classes to private (_ClassName).
  --clean-todos            Strip and remove pending // TODO comments from target files.
  --clean-unused-imports   Remove unused_import and unnecessary_import statements.
  --clean-dead-code        Clean dead null-aware expressions (?. to .) and unreachable code.

SAFETY & CONTROLS:
  --dry-run                Simulate the cleanup without modifying any files on disk.
  --yes, -y                Skip the interactive confirmation prompt and proceed immediately.
  --no-backup              Bypass automatic snapshot backup creation before cleaning (not recommended).

BACKUP & ROLLBACK:
  --backups, --list-backups  List all available snapshot backups with IDs and timestamps.
  --restore <id>             Restore active project files from the specified backup snapshot ID
                             (automatically deletes the snapshot folder after restore to free space).
  --restore-latest           Restore active project files from the most recent backup snapshot.
  --keep-backup              Retain the backup snapshot folder after restoring (disabled by default).
  --clean-backups            Permanently delete all backup snapshots to free disk space.

ANALYSIS FILTER FLAGS:
  --unused-classes,        Scan and report only unused/dead classes and widgets.
  --classes

  --commented,             Scan and report only commented-out files and dead code blocks.
  --comments,
  --commented-code

  --todos-only             Scan and report only TODO comments and pending tasks.
  --diagnostics-only       Scan and report only Dart analyzer diagnostic issues.

  --no-todos               Disable TODO tasks inspection.
  --no-diagnostics         Disable Dart analyzer diagnostics inspection.
  --no-internal            Exclude file-internal only public classes from the report.

FILTERING & TUNING:
  --threshold <number>     Comment ratio percentage (1-100) to flag a file as heavily
                           commented-out.
                           Default: 60 (i.e. files with >= 60% comments).

  --min-lines <number>     Minimum consecutive lines of commented Dart code required
                           to flag a dead block inside an active file.
                           Default: 15 lines.

OUTPUT FORMATS:
  --json [filename]        Save the complete audit report as a .json file in the current
                           working directory (default: detect_unused_code.json) instead of
                           dumping the raw report to the terminal.

  --verbose, -v            Show extended details, including code snippets of detected
                           commented blocks.

  --help, -h               Display this help message and exit.
  --version, -V            Display the package version and exit.

EXAMPLES:
  # Comprehensive audit of current project (all 13 checks)
  detect_unused

  # Clean all unused code safely with confirmation and automatic backup
  detect_unused --clean-all

  # Preview cleanup changes without touching disk
  detect_unused --clean-all --dry-run

  # Clean only unused imports
  detect_unused --clean-unused-imports

  # View all snapshot backups
  detect_unused --backups

  # Rollback project to a previous snapshot
  detect_unused --restore 1
================================================================================
''');
  }

  /// Prints the current package version and exits.
  static void printVersion() {
    print('detect_unused version: $packageVersion');
  }
}

/// Represents an isolated, staged cleanup phase during --clean-all remediation.
class _CleanupStage {
  /// Unique identifier of the cleanup stage.
  final String id;

  /// User-facing descriptive title of the stage.
  final String title;

  /// Emoji representation for terminal UI display.
  final String emoji;

  /// Factory constructing a fresh [UnusedCodeAuditor] configured for this stage's scope.
  final UnusedCodeAuditor Function() createAuditor;

  /// Predicate checking if the stage report contains any actionable items.
  final bool Function(AnalysisReport report) hasTargets;

  /// Returns the count of detected target items in this stage.
  final int Function(AnalysisReport report) targetsCount;

  /// Resolves the files that must be preserved in backup before executing this stage.
  final List<File> Function(AnalysisReport report, CodeCleaner cleaner)
      getTargetFilesToBackup;

  /// Resolves any files marked for deletion in this stage.
  final List<String> Function(AnalysisReport report, CodeCleaner cleaner)
      getFilesMarkedForDeletion;

  /// Executes the cleanup logic for this stage.
  final CleanResult Function(AnalysisReport report, CodeCleaner cleaner) execute;

  /// Creates a new [_CleanupStage].
  _CleanupStage({
    required this.id,
    required this.title,
    required this.emoji,
    required this.createAuditor,
    required this.hasTargets,
    required this.targetsCount,
    required this.getTargetFilesToBackup,
    required this.getFilesMarkedForDeletion,
    required this.execute,
  });
}
