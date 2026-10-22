import 'dart:io';

import '../assets/asset_auditor.dart';
import '../assets/asset_models.dart';
import '../auditor.dart';
import '../backup/backup_manifest.dart';
import '../cleaners/asset_cleaner.dart';
import '../cleaners/code_cleaner.dart';
import '../cleaners/dep_cleaner.dart';
import '../models.dart';
import '../packages/dep_auditor.dart';
import '../packages/package_dep_models.dart';
import '../utils.dart';

/// Represents an isolated, staged cleanup phase during remediation.
class CleanupStage {
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
  final CleanResult Function(AnalysisReport report, CodeCleaner cleaner)
      execute;

  /// Creates a new [CleanupStage].
  CleanupStage({
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

/// Orchestrates multi-stage, health-verified remediation of unused code, assets, and packages.
class StagedCleanupRunner {
  /// The project root directory.
  final Directory projectRoot;

  /// Optional target subdirectory or file filter.
  final String? targetArg;

  /// Comment threshold percentage.
  final int commentThreshold;

  /// Minimum consecutive lines for dead comment blocks.
  final int minBlockLines;

  /// Whether to print verbose progress and diagnostic details.
  final bool verbose;

  /// Flag indicating whether all categories are to be remediated.
  final bool cleanAll;

  /// Whether to delete fully commented-out files.
  final bool cleanCommented;

  /// Whether to strip dead comment blocks.
  final bool cleanDeadBlocks;

  /// Whether to remove dead classes and widgets.
  final bool cleanDeadClasses;

  /// Whether to privatize file-internal public classes.
  final bool privatizeInternal;

  /// Whether to clean pending TODO comments.
  final bool cleanTodos;

  /// Whether to remove unused and redundant imports.
  final bool cleanUnusedImports;

  /// Whether to clean unreachable dead code and dead null-aware expressions.
  final bool cleanDeadCode;

  /// Whether to clean unreferenced media assets and fonts.
  final bool cleanAssets;

  /// Whether to clean unused and duplicate package dependencies in pubspec.yaml.
  final bool cleanPackages;

  /// Whether to ignore/skip dev_dependencies during cleanup.
  final bool ignoreDevDependencies;

  /// Simulation mode without disk modifications.
  final bool dryRun;

  /// Skip confirmation prompt.
  final bool isYes;

  /// Bypass backup creation.
  final bool noBackup;

  /// Optional progress callback during auditing.
  final AuditorProgressCallback? onProgress;

  /// Creates a new [StagedCleanupRunner].
  StagedCleanupRunner({
    required this.projectRoot,
    this.targetArg,
    this.commentThreshold = 60,
    this.minBlockLines = 15,
    this.verbose = false,
    this.cleanAll = false,
    this.cleanCommented = false,
    this.cleanDeadBlocks = false,
    this.cleanDeadClasses = false,
    this.privatizeInternal = false,
    this.cleanTodos = false,
    this.cleanUnusedImports = false,
    this.cleanDeadCode = false,
    this.cleanAssets = false,
    this.cleanPackages = false,
    this.ignoreDevDependencies = false,
    this.dryRun = false,
    this.isYes = false,
    this.noBackup = false,
    this.onProgress,
  });

  /// Executes the staged, health-verified remediation pipeline.
  ///
  /// Returns `0` on success or clean project, or `1` on failure or aborted cleanup.
  int run() {
    final cleaner = CodeCleaner(projectRoot);

    // 1. Initial audit to gather plan overview
    final initialAuditor = UnusedCodeAuditor(
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

    final initialReport = initialAuditor.run(onProgress: onProgress);
    stdout.writeln('\n');

    AssetAnalysisReport? initialAssetReport;
    if (cleanAll || cleanAssets) {
      final assetAuditor = AssetAuditor(workspaceRoot: projectRoot);
      initialAssetReport = assetAuditor.run();
    }

    PackageDependenciesReport? initialDepReport;
    if (cleanAll || cleanPackages) {
      final depAuditor = DependencyAuditor(
        workspaceRoot: projectRoot,
        ignoreDevDependencies: ignoreDevDependencies,
      );
      initialDepReport = depAuditor.run();
    }

    final filesToDelete = (cleanAll || cleanCommented)
        ? initialReport.fullyCommentedFiles
        : <CommentedFileResult>[];
    final blocksToClean = (cleanAll || cleanDeadBlocks)
        ? initialReport.filesWithCommentBlocks
        : <CommentedFileResult>[];
    final deadClassesToClean = (cleanAll || cleanDeadClasses)
        ? initialReport.deadClasses
        : <UnusedClassResult>[];
    final internalClassesToClean = (cleanAll || privatizeInternal)
        ? initialReport.internalOnlyClasses
        : <UnusedClassResult>[];
    final todosToClean =
        (cleanAll || cleanTodos) ? initialReport.todos : <TodoItemResult>[];
    final importsToClean = (cleanAll || cleanUnusedImports)
        ? initialReport.unusedImports
        : <DiagnosticIssueResult>[];
    final deadCodeToClean = (cleanAll || cleanDeadCode)
        ? initialReport.deadCodeAndExpressions
        : <DiagnosticIssueResult>[];
    final assetsToClean = (cleanAll || cleanAssets)
        ? (initialAssetReport?.unusedAssets ?? <UnusedAssetItem>[])
        : <UnusedAssetItem>[];
    final packagesToClean = (cleanAll || cleanPackages)
        ? (initialDepReport?.issues ?? <UnusedDependencyItem>[])
        : <UnusedDependencyItem>[];

    final totalTargets = filesToDelete.length +
        blocksToClean.length +
        deadClassesToClean.length +
        internalClassesToClean.length +
        todosToClean.length +
        importsToClean.length +
        deadCodeToClean.length +
        assetsToClean.length +
        packagesToClean.length;

    if (totalTargets == 0) {
      print(
          '================================================================================');
      print(
          '✨ CLEANUP SUMMARY: Nothing to clean! All code, assets, and packages are in top shape.');
      print(
          '================================================================================');
      return 0;
    }

    // Print planned remediation details
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
        print('     - ${f.file} (${f.blocks.length} block(s)):');
        for (final b in f.blocks) {
          print(
              '       ↳ Lines [L${b.startLine} - L${b.endLine}] (${b.totalLines} lines, ~${b.codeLines} lines code)');
        }
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
    if (deadCodeToClean.isNotEmpty) {
      print(
          '  ⚡ Dead Code & Expressions to Remediate (${deadCodeToClean.length}):');
      for (final d in deadCodeToClean) {
        print('     - ${d.file}:${d.line} (${d.message})');
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
    if (assetsToClean.isNotEmpty) {
      print(
          '  🖼️ Unused Media Assets to Purge (${assetsToClean.length} files, ${initialAssetReport?.totalReclaimableFormatted}):');
      for (final a in assetsToClean.take(10)) {
        print('     - ${a.path} (${a.sizeFormatted})');
      }
      if (assetsToClean.length > 10) {
        print('     ... and ${assetsToClean.length - 10} more');
      }
    }
    if (packagesToClean.isNotEmpty) {
      print(
          '  📦 Unused/Duplicate Packages to Prune (${packagesToClean.length} declarations):');
      for (final p in packagesToClean) {
        print(
            '     - ${p.packageName} in ${p.pubspecRelativePath}:${p.startLine}');
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
          '   re-auditing between each category and verifying code health after each stage.');
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

    // Build ordered stages
    final stages = <CleanupStage>[];

    if (cleanAll || cleanCommented) {
      stages.add(CleanupStage(
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
      stages.add(CleanupStage(
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
      stages.add(CleanupStage(
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
      stages.add(CleanupStage(
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
      stages.add(CleanupStage(
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
      stages.add(CleanupStage(
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
      stages.add(CleanupStage(
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

    int extraStagesCount = 0;
    if (cleanAll || cleanAssets) extraStagesCount++;
    if (cleanAll || cleanPackages) extraStagesCount++;

    final totalStages = stages.length + extraStagesCount;
    final allDeletedFiles = <String>{};
    final allModifiedFiles = <String>{};
    int totalRemediated = 0;
    BackupManifest? sharedBackup;

    print(
        '\n================================================================================');
    print('🚀 STARTING STEP-BY-STEP STAGED REMEDIATION ($totalStages Stages)');
    print(
        '================================================================================');

    int currentStep = 0;

    // Run Code Stages
    for (int i = 0; i < stages.length; i++) {
      currentStep++;
      final stage = stages[i];

      print(
          '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print(
          '▶ [Step $currentStep/$totalStages] ${stage.emoji} Auditing & Remediating: ${stage.title}');
      print(
          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      void stepProgress(int percent, String label) {
        final clamped = percent.clamp(0, 100);
        const barWidth = 24;
        final filled = ((clamped / 100) * barWidth).round();
        final empty = barWidth - filled;
        final bar = '${'█' * filled}${'░' * (empty > 0 ? empty : 0)}';
        final text =
            '\r⏳ [Step $currentStep/$totalStages] [$bar] ${clamped.toString().padLeft(3)}% | $label';
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
              action: 'Clean unused code (step $currentStep: ${stage.title})',
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
          '  ✅ [Step $currentStep/$totalStages] Successfully remediated ${res.totalItemsCleaned} item(s).');

      // Immediate Code Health Check after this stage
      stdout.write('  🔍 Verifying code health after ${stage.title}...');
      var stepHealth = cleaner.verifyProjectHealth();
      if (stepHealth.hasDanglingUris) {
        final removed = cleaner.cleanDanglingUriDirectives(
          stepHealth.errors,
          backup: sharedBackup,
        );
        if (removed.isNotEmpty) {
          print(
              '\n  ✂️ Auto-removed ${removed.length} dangling import/export directive(s) after stage.');
          stepHealth = cleaner.verifyProjectHealth();
        }
      }

      if (stepHealth.hasErrors) {
        print(
            '\n  ⚠️ [Notice] ${stepHealth.errors.length} issue(s) detected during this stage:');
        for (final err in stepHealth.errors.take(3)) {
          print('     - ${err.file}:${err.line} - ${err.message}');
        }
      } else {
        print(' ✅ Healthy (0 errors).');
      }
    }

    // Step 8: Assets
    if (cleanAll || cleanAssets) {
      currentStep++;
      print(
          '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print(
          '▶ [Step $currentStep/$totalStages] 🖼️ Auditing & Cleaning: Unused Media Assets');
      print(
          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final assetAuditor = AssetAuditor(workspaceRoot: projectRoot);
      final assetReport = assetAuditor.run();

      if (assetReport.unusedAssets.isEmpty) {
        print('  ✨ No unused media assets found. Skipping.');
      } else {
        print(
            '  🎯 Found ${assetReport.unusedAssets.length} unused asset(s) (${assetReport.totalReclaimableFormatted}).');
        final assetCleaner = AssetCleaner(
          workspaceRoot: projectRoot,
          backupManager: cleaner.backupManager,
        );
        final assetRes = assetCleaner.clean(
          unusedAssets: assetReport.unusedAssets,
          dryRun: false,
          createBackup: !noBackup,
          sharedBackup: sharedBackup,
        );

        if (sharedBackup == null && assetRes.backupManifest != null) {
          sharedBackup = assetRes.backupManifest;
        }

        totalRemediated += assetRes.deletedFilesCount;
        print(
            '  ✅ [Step $currentStep/$totalStages] Purged ${assetRes.deletedFilesCount} asset(s) (${assetRes.formattedBytesFreed}).');

        // Verify Code Health after Assets
        stdout.write('  🔍 Verifying code health after Assets cleanup...');
        final assetHealth = cleaner.verifyProjectHealth();
        if (assetHealth.hasErrors) {
          print(
              '\n  ⚠️ [Notice] ${assetHealth.errors.length} issue(s) detected:');
          for (final err in assetHealth.errors.take(3)) {
            print('     - ${err.file}:${err.line} - ${err.message}');
          }
        } else {
          print(' ✅ Healthy (0 errors).');
        }
      }
    }

    // Step 9: Packages
    if (cleanAll || cleanPackages) {
      currentStep++;
      print(
          '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print(
          '▶ [Step $currentStep/$totalStages] 📦 Auditing & Pruning: Unused & Duplicate Packages');
      print(
          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final depAuditor = DependencyAuditor(
        workspaceRoot: projectRoot,
        ignoreDevDependencies: ignoreDevDependencies,
      );
      final depReport = depAuditor.run();

      if (depReport.issues.isEmpty) {
        print('  ✨ No unused or duplicate package dependencies. Skipping.');
      } else {
        print(
            '  🎯 Found ${depReport.issues.length} package dependency issue(s).');
        final depCleaner = DependencyCleaner(
          workspaceRoot: projectRoot,
          backupManager: cleaner.backupManager,
        );
        final depRes = depCleaner.clean(
          issues: depReport.issues,
          dryRun: false,
          createBackup: !noBackup,
          sharedBackup: sharedBackup,
        );

        if (sharedBackup == null && depRes.backupManifest != null) {
          sharedBackup = depRes.backupManifest;
        }

        totalRemediated += depRes.removedCount;
        print(
            '  ✅ [Step $currentStep/$totalStages] Pruned ${depRes.removedCount} declaration(s) across ${depRes.updatedPubspecsCount} pubspec(s).');

        // Verify Code Health after Packages
        stdout.write('  🔍 Verifying code health after Packages cleanup...');
        final depHealth = cleaner.verifyProjectHealth();
        if (depHealth.hasErrors) {
          print(
              '\n  ⚠️ [Notice] ${depHealth.errors.length} issue(s) detected:');
          for (final err in depHealth.errors.take(3)) {
            print('     - ${err.file}:${err.line} - ${err.message}');
          }
        } else {
          print(' ✅ Healthy (0 errors).');
        }
      }
    }

    print(
        '\n================================================================================');
    print('🎉 STEP-BY-STEP STAGED CLEANUP COMPLETED');
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
      print('     Or instant undo:  detect_unused --undo');
    }
    print(
        '--------------------------------------------------------------------------------');

    // Final comprehensive health check across entire project
    stdout
        .write('🔍 Verifying final project compilation and analyzer health...');
    var health = cleaner.verifyProjectHealth();

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
}
