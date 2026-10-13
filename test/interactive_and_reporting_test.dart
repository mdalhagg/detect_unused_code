import 'dart:io';

import 'package:detect_unused_code/detect_unused_code.dart';
import 'package:test/test.dart';

void main() {
  group('MarkdownReporter Tests', () {
    test('Generates valid Markdown report with metrics table and attribution',
        () {
      final codeReport = AnalysisReport(
        targetPath: '.',
        totalTargetDartFiles: 20,
        totalProjectDartFiles: 25,
        deadClasses: [
          UnusedClassResult(
            name: 'OldDeadWidget',
            file: '/dummy/lib/old_dead_widget.dart',
            relPath: 'lib/old_dead_widget.dart',
            fileUri: 'file:///dummy/lib/old_dead_widget.dart',
            line: 10,
            category: 'Widget/Page',
            isPrivate: false,
            type: 'PUBLIC_ZERO_EXTERNAL',
            severity: 'CRITICAL',
            reason: 'Zero references found',
            internalMatches: 0,
            externalMatches: 0,
          ),
        ],
        internalOnlyClasses: [],
        fullyCommentedFiles: [
          CommentedFileResult(
            file: 'lib/fully_commented.dart',
            absolutePath: '/dummy/lib/fully_commented.dart',
            fileUri: 'file:///dummy/lib/fully_commented.dart',
            totalNonEmptyLines: 50,
            commentLinesCount: 50,
            commentRatio: 100,
            isFullyCommented: true,
            isHighCommentRatio: true,
            commentedClasses: ['AbandonedClass'],
            blocks: [],
          ),
        ],
        highRatioFiles: [],
        filesWithCommentBlocks: [
          CommentedFileResult(
            file: 'lib/active.dart',
            absolutePath: '/dummy/lib/active.dart',
            fileUri: 'file:///dummy/lib/active.dart',
            totalNonEmptyLines: 100,
            commentLinesCount: 20,
            commentRatio: 20,
            isFullyCommented: false,
            isHighCommentRatio: false,
            commentedClasses: [],
            blocks: [
              CommentBlockResult(
                startLine: 12,
                endLine: 30,
                totalLines: 19,
                codeLines: 10,
                sample: '// dead block sample',
              ),
            ],
          ),
        ],
        todos: [
          TodoItemResult(
            file: 'lib/active.dart',
            absolutePath: '/dummy/lib/active.dart',
            fileUri: 'file:///dummy/lib/active.dart',
            line: 5,
            message: 'fix this later',
            rawLine: '// TODO: fix this later',
          ),
        ],
        diagnostics: [
          DiagnosticIssueResult(
            file: 'lib/active.dart',
            absolutePath: '/dummy/lib/active.dart',
            fileUri: 'file:///dummy/lib/active.dart',
            line: 2,
            column: 8,
            code: 'unused_import',
            message: 'Unused import',
            severity: 'INFO',
          ),
        ],
      );

      final dummyPackage = PackageDescriptor(
        name: 'my_app',
        pubspecFile: File('/dummy/pubspec.yaml'),
        packageRootDir: Directory('/dummy'),
      );

      final assetReport = AssetAnalysisReport(
        scannedPackages: [dummyPackage],
        totalScannedAssets: 5,
        unusedAssets: [
          UnusedAssetItem(
            path: 'assets/images/banner.png',
            packageRelativePath: 'assets/images/banner.png',
            absolutePath: '/dummy/assets/images/banner.png',
            fileUri: 'file:///dummy/assets/images/banner.png',
            sizeInBytes: 1024 * 500,
            sizeFormatted: '500.0 KB',
            category: AssetCategory.image,
            ownerPackage: dummyPackage,
            isExplicitInPubspec: true,
          ),
        ],
        totalReclaimableBytes: 1024 * 500,
        totalReclaimableFormatted: '500.0 KB',
      );

      final depReport = PackageDependenciesReport(
        scannedPubspecsCount: 1,
        totalDependenciesScanned: 10,
        issues: [
          UnusedDependencyItem(
            packageName: 'http',
            scope: DependencyScope.regular,
            issueType: DependencyIssueType.unused,
            pubspecFile: File('/dummy/pubspec.yaml'),
            pubspecRelativePath: 'pubspec.yaml',
            owningPackageName: 'my_app',
            startLine: 10,
            endLine: 10,
            rawDeclaration: '  http: ^0.13.0',
            description: 'Unused package dependency',
          ),
        ],
      );

      final reporter = MarkdownReporter(
        report: codeReport,
        projectRoot: Directory('/dummy/my_app'),
        depReport: depReport,
        assetReport: assetReport,
      );

      final markdown = reporter.generate();

      // Verify title and badges
      expect(markdown, contains('# 🔎 Detect Unused Code Audit Report'));
      expect(markdown, contains('my_app'));
      expect(markdown, contains('Action Recommended'));

      // Verify summary table
      expect(markdown, contains('**Dead Classes & Widgets**'));
      expect(markdown, contains('**100% Commented Files**'));
      expect(markdown, contains('**Files with Dead Code Blocks**'));
      expect(markdown, contains('**Unused & Redundant Imports**'));
      expect(markdown, contains('**Unused Media Assets & Fonts**'));
      expect(markdown, contains('**Unused / Duplicate Packages**'));
      expect(markdown, contains('500.0 KB'));

      // Verify item details inside collapsible sections
      expect(markdown, contains('OldDeadWidget'));
      expect(markdown, contains('lib/fully_commented.dart'));
      expect(markdown, contains('assets/images/banner.png'));
      expect(markdown, contains('`http`'));

      // Verify user attribution
      expect(markdown, contains('mdalhagg'));
      expect(
          markdown, contains('https://github.com/mdalhagg/detect_unused_code'));
    });

    test('Saves markdown report to file system', () {
      final tempDir = Directory.systemTemp.createTempSync('report_test_');
      try {
        final codeReport = AnalysisReport(
          targetPath: '.',
          totalTargetDartFiles: 5,
          totalProjectDartFiles: 5,
          deadClasses: [],
          internalOnlyClasses: [],
          fullyCommentedFiles: [],
          highRatioFiles: [],
          filesWithCommentBlocks: [],
          todos: [],
          diagnostics: [],
        );

        final reporter = MarkdownReporter(
          report: codeReport,
          projectRoot: tempDir,
        );

        final targetFile = '${tempDir.path}/TEST_REPORT.md';
        final savedFile = reporter.saveToFile(targetFile);

        expect(savedFile.existsSync(), isTrue);
        expect(savedFile.readAsStringSync(), contains('Detect Unused Code'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Instant Undo & Rollback Tests', () {
    test('BackupManager correctly records, recovers, and unrolls snapshots',
        () {
      final tempDir = Directory.systemTemp.createTempSync('undo_test_');
      try {
        final testFile = File('${tempDir.path}/test_subject.dart');
        testFile.writeAsStringSync('void main() { print("original"); }');

        final manager = BackupManager(tempDir);

        // 1. Create a backup
        final manifest = manager.createBackup(
          action: 'Test Pre-Clean Backup',
          filesToBackup: [testFile],
        );

        final backupId = manifest.id;
        final latest = manager.getLatestBackup();
        expect(latest?.id, equals(backupId));

        // 2. Modify the test file (simulating cleaner)
        testFile.writeAsStringSync('// file was cleared or wiped');

        // 3. Perform restore (Undo)
        final result =
            manager.restoreBackup(backupId, deleteAfterRestore: true);
        expect(result.restoredFiles.length, equals(1));
        expect(testFile.readAsStringSync(),
            equals('void main() { print("original"); }'));

        // 4. Verify snapshot was deleted after restore
        expect(manager.listBackups().isEmpty, isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
