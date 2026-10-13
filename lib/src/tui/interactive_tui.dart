import 'dart:io';

import '../assets/asset_auditor.dart';
import '../assets/asset_models.dart';
import '../auditor.dart';
import '../backup/backup_manager.dart';
import '../cleaners/staged_cleaner.dart';
import '../models.dart';
import '../packages/dep_auditor.dart';
import '../packages/package_dep_models.dart';
import '../reporters/markdown_reporter.dart';
import '../version.dart';

/// Interactive Terminal UI (TUI) control dashboard for detect_unused_code.
///
/// Built with zero external dependencies using standard dart:io stdin/stdout.
class InteractiveTui {
  /// The project root directory.
  final Directory projectRoot;

  /// Audit options.
  final AuditorOptions options;

  /// Creates a new [InteractiveTui] instance.
  InteractiveTui({
    required this.projectRoot,
    this.options = const AuditorOptions(),
  });

  // Selected categories map
  final Map<int, bool> _selected = {
    1: true, // Dead Classes & Widgets
    2: true, // Dead Commented Blocks
    3: true, // 100% Commented Files
    4: true, // Unused External Packages
    5: true, // Unused Media Assets & Fonts
    6: false, // TODO Pending Tasks (default off for cleanup)
    7: true, // Unused & Redundant Imports
    8: true, // Dead Code & Null-Aware
  };

  /// Starts the interactive session loop.
  void start() {
    print('\n⏳ Initializing workspace audit...');

    final auditor =
        UnusedCodeAuditor(projectRoot: projectRoot, options: options);
    var report = auditor.run();

    final depAuditor = DependencyAuditor(workspaceRoot: projectRoot);
    var depReport = depAuditor.run();

    final assetAuditor = AssetAuditor(workspaceRoot: projectRoot);
    var assetReport = assetAuditor.run();

    bool running = true;
    while (running) {
      _renderDashboard(report, depReport, assetReport);
      stdout.write('Select an option: ');
      final input = stdin.readLineSync()?.trim().toUpperCase() ?? '';

      if (input == 'Q' || input == 'QUIT' || input == 'EXIT') {
        print('\n👋 Exiting interactive mode. Goodbye!\n');
        running = false;
        break;
      }

      final numChoice = int.tryParse(input);
      if (numChoice != null && _selected.containsKey(numChoice)) {
        _selected[numChoice] = !_selected[numChoice]!;
        continue;
      }

      switch (input) {
        case 'A':
          final allOn = _selected.values.every((v) => v);
          for (final k in _selected.keys) {
            _selected[k] = !allOn;
          }
          break;

        case 'V':
          _viewItemDetails(report, depReport, assetReport);
          break;

        case 'D':
          _executeClean(
            report: report,
            depReport: depReport,
            assetReport: assetReport,
            dryRun: true,
          );
          print('\nPress [Enter] to return to dashboard...');
          stdin.readLineSync();
          break;

        case 'C':
          _executeClean(
            report: report,
            depReport: depReport,
            assetReport: assetReport,
            dryRun: false,
          );
          print('\n⏳ Refreshing workspace audit...');
          report = auditor.run();
          depReport = depAuditor.run();
          assetReport = assetAuditor.run();
          print('Press [Enter] to return to dashboard...');
          stdin.readLineSync();
          break;

        case 'U':
          _executeUndo();
          print('\n⏳ Refreshing workspace audit...');
          report = auditor.run();
          depReport = depAuditor.run();
          assetReport = assetAuditor.run();
          print('Press [Enter] to return to dashboard...');
          stdin.readLineSync();
          break;

        case 'M':
          final reporter = MarkdownReporter(
            report: report,
            projectRoot: projectRoot,
            depReport: depReport,
            assetReport: assetReport,
          );
          const outName = 'detect_unused_report.md';
          reporter.saveToFile(outName);
          print(
              '\n📄 Markdown report generated: ${Directory.current.path}/$outName');
          print('Press [Enter] to continue...');
          stdin.readLineSync();
          break;

        default:
          print('⚠️ Unknown option "$input". Try again.');
      }
    }
  }

  void _renderDashboard(
    AnalysisReport report,
    PackageDependenciesReport depReport,
    AssetAnalysisReport assetReport,
  ) {
    stdout.writeln();
    stdout.writeln(
        '┌────────────────────────────────────────────────────────────────────────┐');
    stdout.writeln(
        '│ 🔍 DETECT_UNUSED_CODE - INTERACTIVE CONTROL DASHBOARD (v$packageVersion)         │');
    stdout.writeln(
        '│ ⚡ Powered by @mdalhagg | https://github.com/mdalhagg                  │');
    stdout.writeln(
        '├────────────────────────────────────────────────────────────────────────┤');

    _printCategoryLine(
        1, '💀 Dead Classes & Widgets', '${report.deadClasses.length} found');
    _printCategoryLine(2, '📦 Dead Commented Code Blocks',
        '${report.filesWithCommentBlocks.length} files');
    _printCategoryLine(3, '🚫 100% Commented Files',
        '${report.fullyCommentedFiles.length} files');
    _printCategoryLine(4, '📦 Unused External Packages',
        '${depReport.issues.length} packages');
    _printCategoryLine(5, '🖼️ Unused Media Assets & Fonts',
        '${assetReport.unusedAssets.length} files (${assetReport.totalReclaimableFormatted})');
    _printCategoryLine(
        6, '📋 TODO Pending Tasks', '${report.todos.length} notes');
    _printCategoryLine(7, '🧹 Unused & Redundant Imports',
        '${report.unusedImports.length} imports');
    _printCategoryLine(8, '💀 Dead Code & Null-Aware',
        '${report.deadCodeAndExpressions.length} items');

    stdout.writeln(
        '├────────────────────────────────────────────────────────────────────────┤');
    stdout.writeln(
        '│ Commands:                                                              │');
    stdout.writeln(
        '│  [1-8] Toggle category     [A] Toggle All        [V] View details      │');
    stdout.writeln(
        '│  [D] Preview (Dry Run)     [C] Clean Selected    [U] Undo last action  │');
    stdout.writeln(
        '│  [M] Export Markdown       [Q] Quit                                    │');
    stdout.writeln(
        '└────────────────────────────────────────────────────────────────────────┘');
  }

  void _printCategoryLine(int id, String title, String countStr) {
    final checked = _selected[id] == true ? '[X]' : '[ ]';
    final lineContent = '│ [$id] $checked $title ($countStr)';
    final padded = '${lineContent.padRight(73)}│';
    stdout.writeln(padded);
  }

  void _viewItemDetails(
    AnalysisReport report,
    PackageDependenciesReport depReport,
    AssetAnalysisReport assetReport,
  ) {
    stdout.writeln(
        '\n================== 🔎 DETAILED AUDIT FINDINGS ==================');

    if (report.deadClasses.isNotEmpty) {
      stdout.writeln(
          '\n💀 [Dead Classes & Widgets] (${report.deadClasses.length}):');
      for (final c in report.deadClasses.take(15)) {
        stdout
            .writeln('   - [${c.category}] ${c.name} (${c.relPath}:${c.line})');
      }
      if (report.deadClasses.length > 15) {
        stdout.writeln(
            '   ↳ ...and ${report.deadClasses.length - 15} more classes');
      }
    }

    if (depReport.issues.isNotEmpty) {
      stdout.writeln(
          '\n📦 [Unused / Duplicate Packages] (${depReport.issues.length}):');
      for (final p in depReport.issues) {
        stdout.writeln(
            '   - ${p.packageName} (${p.scope.name}) in ${p.pubspecRelativePath}');
      }
    }

    if (assetReport.unusedAssets.isNotEmpty) {
      stdout.writeln(
          '\n🖼️ [Unused Media Assets & Fonts] (${assetReport.unusedAssets.length} - ${assetReport.totalReclaimableFormatted}):');
      for (final a in assetReport.unusedAssets.take(15)) {
        stdout.writeln('   - ${a.path} (${a.sizeFormatted})');
      }
      if (assetReport.unusedAssets.length > 15) {
        stdout.writeln(
            '   ↳ ...and ${assetReport.unusedAssets.length - 15} more assets');
      }
    }

    if (report.fullyCommentedFiles.isNotEmpty) {
      stdout.writeln(
          '\n🚫 [100% Commented Files] (${report.fullyCommentedFiles.length}):');
      for (final f in report.fullyCommentedFiles) {
        stdout.writeln('   - ${f.file}');
      }
    }

    if (report.filesWithCommentBlocks.isNotEmpty) {
      stdout.writeln(
          '\n📦 [Active Files with Dead Blocks] (${report.filesWithCommentBlocks.length}):');
      for (final f in report.filesWithCommentBlocks) {
        stdout.writeln('   - ${f.file} (${f.blocks.length} block(s))');
      }
    }

    if (report.unusedImports.isNotEmpty) {
      stdout.writeln('\n🧹 [Unused Imports] (${report.unusedImports.length}):');
      for (final imp in report.unusedImports.take(10)) {
        stdout.writeln('   - ${imp.file}:${imp.line} -> ${imp.message}');
      }
      if (report.unusedImports.length > 10) {
        stdout.writeln(
            '   ↳ ...and ${report.unusedImports.length - 10} more imports');
      }
    }

    stdout.writeln(
        '================================================================');
    stdout.write('\nPress [Enter] to return to dashboard...');
    stdin.readLineSync();
  }

  void _executeClean({
    required AnalysisReport report,
    required PackageDependenciesReport depReport,
    required AssetAnalysisReport assetReport,
    required bool dryRun,
  }) {
    final runner = StagedCleanupRunner(
      projectRoot: projectRoot,
      targetArg: options.targetPath,
      commentThreshold: options.commentThreshold,
      minBlockLines: options.minBlockLines,
      verbose: options.verbose,
      cleanDeadClasses: _selected[1] == true,
      cleanDeadBlocks: _selected[2] == true,
      cleanCommented: _selected[3] == true,
      cleanPackages: _selected[4] == true,
      cleanAssets: _selected[5] == true,
      cleanTodos: _selected[6] == true,
      cleanUnusedImports: _selected[7] == true,
      cleanDeadCode: _selected[8] == true,
      dryRun: dryRun,
      isYes: true, // User triggered action directly from the interactive menu
      noBackup: false,
    );

    runner.run();
  }

  void _executeUndo() {
    print('\n↺ Rolling back to latest snapshot...');
    final manager = BackupManager(projectRoot);
    final latest = manager.getLatestBackup();
    if (latest == null) {
      print('⚠️ No snapshot backups found to restore.');
      return;
    }

    final res = manager.restoreBackup(latest.id, deleteAfterRestore: true);
    if (res.success) {
      print(
          '✅ Undo successful: Restored ${res.restoredFiles.length} file(s) from snapshot #${latest.id}.');
      for (final f in res.restoredFiles) {
        print('   ↳ Restored: $f');
      }
    } else {
      print('❌ Undo failed: ${res.message}');
    }
  }
}
