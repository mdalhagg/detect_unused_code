import 'dart:convert';
import 'dart:io';

import 'auditor.dart';
import 'models.dart';
import 'utils.dart';

class CliRunner {
  final List<String> args;

  CliRunner(this.args);

  int run() {
    if (args.contains('--help') || args.contains('-h')) {
      printHelp();
      return 0;
    }

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

    final onlyUnusedClasses = args.contains('--unused-classes') || args.contains('--classes');
    final onlyCommented = args.contains('--commented') ||
        args.contains('--commented-code') ||
        args.contains('--comments');
    final includeInternal = args.contains('--include-internal');
    final verbose = args.contains('--verbose') || args.contains('-v');

    int commentThreshold = 60;
    final thresholdIdx = args.indexOf('--threshold');
    if (thresholdIdx != -1 && thresholdIdx + 1 < args.length) {
      final p = int.tryParse(args[thresholdIdx + 1]);
      if (p != null && p > 0 && p <= 100) commentThreshold = p;
    }

    int minBlockLines = 15;
    final minLinesIdx = args.indexOf('--min-lines');
    if (minLinesIdx != -1 && minLinesIdx + 1 < args.length) {
      final p = int.tryParse(args[minLinesIdx + 1]);
      if (p != null && p > 0) minBlockLines = p;
    }

    final targetArg = extractTargetArg(args);
    final projectRoot = findProjectOrWorkspaceRoot();

    final options = AuditorOptions(
      targetPath: targetArg,
      runClassAnalysis: !onlyCommented,
      runCommentAnalysis: !onlyUnusedClasses,
      includeInternal: includeInternal,
      commentThreshold: commentThreshold,
      minBlockLines: minBlockLines,
      verbose: verbose,
    );

    final auditor = UnusedCodeAuditor(
      projectRoot: projectRoot,
      options: options,
    );

    void updateProgress(int percent, String label) {
      final clamped = percent.clamp(0, 100);
      const barWidth = 28;
      final filled = ((clamped / 100) * barWidth).round();
      final empty = barWidth - filled;
      final bar = '${'█' * filled}${'░' * (empty > 0 ? empty : 0)}';
      final text = '\r⏳ Loading & Analyzing: [$bar] ${clamped.toString().padLeft(3)}% | $label';
      stdout.write(text);
    }

    final report = auditor.run(onProgress: updateProgress);
    stdout.writeln('\n');

    if (isJson) {
      final jsonMap = report.toJson(includeInternal: includeInternal);
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);

      final outputFile = File('${Directory.current.path}/$jsonFileName');
      outputFile.writeAsStringSync(jsonString);

      print('================================================================================');
      print('✅ JSON Audit Report generated successfully!');
      print('📁 File Saved: [${outputFile.path}]');
      print('📄 Dart Files Scanned:       ${report.totalTargetDartFiles}');
      print('💀 Dead Classes Found:       ${report.deadClasses.length}');
      if (includeInternal) {
        print('⚠️ Internal-only Classes:    ${report.internalOnlyClasses.length}');
      }
      print('🚫 Fully Commented Files:    ${report.fullyCommentedFiles.length}');
      print('📦 Files with Dead Blocks:   ${report.filesWithCommentBlocks.length}');
      print('================================================================================\n');

      return (report.deadClasses.isNotEmpty || report.fullyCommentedFiles.isNotEmpty) ? 1 : 0;
    }

    _printConsoleReport(report, options, projectRoot);

    return (report.deadClasses.isNotEmpty || report.fullyCommentedFiles.isNotEmpty) ? 1 : 0;
  }

  void _printConsoleReport(
    AnalysisReport report,
    AuditorOptions options,
    Directory projectRoot,
  ) {
    print('\n${'=' * 78}');
    print('🔎 DEAD CODE & UNUSED CLASSES AUDITOR REPORT');
    print('📁 Target Scope: [${report.targetPath}]');
    print('📄 Dart Files:   ${report.totalTargetDartFiles} scanned (out of ${report.totalProjectDartFiles} total in project)');
    print('=' * 78);

    if (options.runCommentAnalysis) {
      if (report.fullyCommentedFiles.isNotEmpty) {
        print('\n🚫 【1. Fully Commented-Out Files (100% Comments)】 - (${report.fullyCommentedFiles.length} files):');
        print('   (These files contain entirely commented-out code and can be safely deleted or restored)');
        for (final f in report.fullyCommentedFiles) {
          final classesHint = f.commentedClasses.isNotEmpty
              ? '\n      ↳ Commented classes found inside: [ ${f.commentedClasses.join(', ')} ]'
              : '';
          print('   🔴 [${f.commentRatio}% comments | ${f.totalNonEmptyLines} lines]: ${f.file}$classesHint');
        }
      }

      if (report.highRatioFiles.isNotEmpty) {
        print('\n⚠️ 【2. Heavily Commented Files (>= ${options.commentThreshold}% comments)】 - (${report.highRatioFiles.length} files):');
        for (final f in report.highRatioFiles) {
          print('   🟠 [${f.commentRatio}% comments | ${f.commentLinesCount}/${f.totalNonEmptyLines} lines]: ${f.file}');
        }
      }

      if (report.filesWithCommentBlocks.isNotEmpty) {
        print('\n📦 【3. Active Files with Large Commented Code Blocks (>= ${options.minBlockLines} lines)】 - (${report.filesWithCommentBlocks.length} files):');
        for (final f in report.filesWithCommentBlocks) {
          print('   🟡 ${f.file}');
          for (final b in f.blocks) {
            print('      ↳ Lines [L${b.startLine} - L${b.endLine}] (${b.totalLines} lines, ${b.codeLines} lines containing Dart syntax)');
            if (options.verbose && b.sample.isNotEmpty) {
              print('         Sample:\n         ${b.sample.replaceAll('\n', '\n         ')}');
            }
          }
        }
      }

      if (report.fullyCommentedFiles.isEmpty &&
          report.highRatioFiles.isEmpty &&
          report.filesWithCommentBlocks.isEmpty) {
        print('\n✅ Commented Code: No commented-out files or dead code blocks detected in this scope.');
      }
    }

    if (options.runClassAnalysis) {
      print('\n${'-' * 78}');
      if (report.deadClasses.isNotEmpty) {
        print('\n💀 【4. Unused & Dead Classes (Zero Project-wide References)】 - (${report.deadClasses.length} classes):');
        print('   (Classes declared in this scope that have 0 external references across the entire workspace)');

        final byCategory = <String, List<UnusedClassResult>>{};
        for (final c in report.deadClasses) {
          byCategory.putIfAbsent(c.category, () => []).add(c);
        }

        for (final entry in byCategory.entries) {
          print('\n   🔹 Category [${entry.key}] (${entry.value.length}):');
          for (final c in entry.value) {
            final typeTag = c.isPrivate ? '[Private]' : '[Public]';
            print('      ❌ $typeTag ${c.name.padRight(32)} 📍 ${c.relPath}:${c.line}');
          }
        }
      } else {
        print('\n✅ Unused Classes: All classes in this scope are actively used across the project.');
      }

      if (options.includeInternal) {
        if (report.internalOnlyClasses.isNotEmpty) {
          print('\n⚠️ 【5. File-Internal Only Public Classes】 - (${report.internalOnlyClasses.length} classes):');
          print('   (Public classes with 0 external references, used only within their declaring file)');
          for (final c in report.internalOnlyClasses) {
            print('      🔸 ${c.name.padRight(32)} (Internal references: ${c.internalMatches}) 📍 ${c.relPath}:${c.line}');
          }
        }
      } else if (report.internalOnlyClasses.isNotEmpty) {
        print('\n💡 Note: Found ${report.internalOnlyClasses.length} public classes used internally only. To display them, re-run with --include-internal');
      }
    }

    print('\n${'=' * 78}');
    print('📊 FINAL AUDIT SUMMARY:');
    print('   - Fully commented-out files:          ${report.fullyCommentedFiles.length}');
    for (final f in report.fullyCommentedFiles) {
      print('      ↳ ${f.file}');
    }
    print('   - Heavily commented files:            ${report.highRatioFiles.length}');
    for (final f in report.highRatioFiles) {
      print('      ↳ ${f.file}');
    }
    print('   - Files with dead code blocks:        ${report.filesWithCommentBlocks.length}');
    for (final f in report.filesWithCommentBlocks) {
      print('      ↳ ${f.file}');
    }
    print('   - Dead classes (Zero usages):         ${report.deadClasses.length}');
    if (report.deadClasses.isNotEmpty) {
      final deadByFile = <String, List<String>>{};
      for (final c in report.deadClasses) {
        deadByFile.putIfAbsent(c.relPath, () => []).add(c.name);
      }
      for (final entry in deadByFile.entries) {
        print('      ↳ ${entry.key}  :: [${entry.value.join(', ')}]');
      }
    }
    if (options.runClassAnalysis) {
      print('   - File-internal only classes:         ${report.internalOnlyClasses.length}');
      if (options.includeInternal && report.internalOnlyClasses.isNotEmpty) {
        final internalByFile = <String, List<String>>{};
        for (final c in report.internalOnlyClasses) {
          internalByFile.putIfAbsent(c.relPath, () => []).add(c.name);
        }
        for (final entry in internalByFile.entries) {
          print('      ↳ ${entry.key}  :: [${entry.value.join(', ')}]');
        }
      }
    }
    print('${'=' * 78}\n');
  }

  static String? extractTargetArg(List<String> args) {
    for (int i = 0; i < args.length; i++) {
      final a = args[i];
      final match = RegExp(r'^--(?:url|path|target)=(.*)$').firstMatch(a);
      if (match != null) {
        final raw = match.group(1)!;
        final val = cleanInputPath(raw);
        if (val.isNotEmpty) return val;
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
      if (a.startsWith('--')) continue;
      if (i > 0 &&
          (args[i - 1] == '--threshold' ||
              args[i - 1] == '--min-lines' ||
              args[i - 1] == '--json')) continue;
      return cleanInputPath(a);
    }
    return null;
  }

  static void printHelp() {
    print('''
================================================================================
  detect_unused_code
  A fast, zero-dependency Dart & Flutter dead code and unused code auditor.
================================================================================

USAGE:
  detect_unused [OPTIONS]
  detect_unused_code [OPTIONS]
  dart run detect_unused_code [OPTIONS]
  dart run detect_unused_code:detect_unused [OPTIONS]

TARGET SPECIFICATION:
  --url=<path>             Target directory or specific Dart file to scan.
                           Can also be written as: --url "path" or simply as a positional argument.
                           Accepts relative or absolute paths (e.g. "lib/features/auth").
                           Default: Scans the entire project if omitted.
  --path=<path>            Aliases for --url.
  --target=<path>

ANALYSIS MODES:
  --unused-classes,        Scan and report only unused/dead classes and widgets.
  --classes                (Skips commented code inspection).

  --commented,             Scan and report only commented-out files and dead code blocks.
  --comments,              (Skips unused classes inspection).
  --commented-code

  (Default: If neither mode flag is specified, BOTH analyses are performed).

FILTERING & TUNING:
  --include-internal       Include public classes that are only referenced internally
                           within their own file (0 external usages). Useful to detect
                           orphaned widgets/models that can be converted to private (_)
                           or safely removed.

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

EXAMPLES:
  # Scan current project using short command
  detect_unused

  # Scan a specific directory
  detect_unused --path="lib/presentation/pages"

  # Scan a single file
  detect_unused lib/models/user_model.dart

  # Unused classes only including file-internal ones
  detect_unused --unused-classes --include-internal

  # Export JSON for CI/CD
  detect_unused --json
================================================================================
''');
  }
}
