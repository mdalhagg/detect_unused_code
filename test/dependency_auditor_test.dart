import 'dart:io';

import 'package:detect_unused_code/detect_unused_code.dart';
import 'package:test/test.dart';

void main() {
  group('Multi-Pubspec & Dependency Engine Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('detect_unused_dep_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Isolated per-package scoping for multi-pubspec dependencies', () {
      // 1. Root package pubspec
      final rootPub = File('${tempDir.path}/pubspec.yaml');
      rootPub.writeAsStringSync('''
name: root_app
dependencies:
  http: ^1.2.0
  intl: ^0.19.0
  unused_root: ^1.0.0
dev_dependencies:
  lints: ^5.1.1
  unused_dev_root: ^2.0.0
''');

      // Root imports ONLY http
      final rootDart = File('${tempDir.path}/lib/main.dart')
        ..createSync(recursive: true);
      rootDart.writeAsStringSync(
          "import 'package:http/http.dart';\nvoid main() {}");

      // 2. Sub-package in packages/auth
      final subDir = Directory('${tempDir.path}/packages/auth')
        ..createSync(recursive: true);
      final subPub = File('${subDir.path}/pubspec.yaml');
      subPub.writeAsStringSync('''
name: auth
dependencies:
  intl: ^0.19.0
  unused_sub: ^1.0.0
dev_dependencies:
  test: ^1.24.0
''');

      // Sub-package imports ONLY intl
      final subDart = File('${subDir.path}/lib/auth.dart')
        ..createSync(recursive: true);
      subDart
          .writeAsStringSync("import 'package:intl/intl.dart';\nclass Auth {}");

      // Run DependencyAuditor
      final auditor = DependencyAuditor(workspaceRoot: tempDir);
      final report = auditor.run();

      expect(report.scannedPubspecsCount, equals(2));

      // Root has unused:
      // - intl (declared in root but only imported inside sub-package!)
      // - unused_root
      // - unused_dev_root
      // (http is used, lints is protected by tool whitelist)
      final rootIssues = report.issues
          .where((i) => i.owningPackageName == 'root_app')
          .map((i) => i.packageName)
          .toList();
      expect(rootIssues, contains('unused_root'));
      expect(rootIssues, contains('unused_dev_root'));
      expect(rootIssues, contains('intl')); // Scoping isolation verified!
      expect(rootIssues, isNot(contains('http')));
      expect(rootIssues, isNot(contains('lints'))); // Whitelist guard verified!

      // Sub-package has unused:
      // - unused_sub
      // (intl is used, test is protected by tool whitelist)
      final subIssues = report.issues
          .where((i) => i.owningPackageName == 'auth')
          .map((i) => i.packageName)
          .toList();
      expect(subIssues, contains('unused_sub'));
      expect(subIssues, isNot(contains('intl')));
      expect(subIssues, isNot(contains('test')));
    });

    test('Duplicate dependencies detection in pubspec.yaml', () {
      final pubFile = File('${tempDir.path}/pubspec.yaml');
      pubFile.writeAsStringSync('''
name: dup_test
dependencies:
  provider: ^6.1.0
  shared_preferences: ^2.2.0
  provider: ^6.1.2
dev_dependencies:
  provider: ^6.1.0
''');

      final dartFile = File('${tempDir.path}/lib/main.dart')
        ..createSync(recursive: true);
      dartFile.writeAsStringSync('''
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
void main() {}
''');

      final auditor = DependencyAuditor(workspaceRoot: tempDir);
      final report = auditor.run();

      // There should be 2 duplicate issues for 'provider':
      // 1) The duplicate line in dependencies
      // 2) The redundant entry in dev_dependencies
      final dups = report.duplicateDependencies;
      expect(dups.length, equals(2));
      expect(dups.every((d) => d.packageName == 'provider'), isTrue);
      expect(dups.every((d) => d.issueType == DependencyIssueType.duplicate),
          isTrue);
    });

    test(
        'DependencyCleaner: removes single-line and multi-line blocks with backup',
        () {
      final pubFile = File('${tempDir.path}/pubspec.yaml');
      pubFile.writeAsStringSync('''
name: clean_test
dependencies:
  keep_me: ^1.0.0
  remove_single: ^2.0.0
  remove_multiline:
    git:
      url: https://github.com/example/repo.git
      ref: main
  also_keep: ^3.0.0
''');

      final dartFile = File('${tempDir.path}/lib/main.dart')
        ..createSync(recursive: true);
      dartFile.writeAsStringSync('''
import 'package:keep_me/keep_me.dart';
import 'package:also_keep/also_keep.dart';
void main() {}
''');

      final auditor = DependencyAuditor(workspaceRoot: tempDir);
      final report = auditor.run();

      expect(report.issues.length, equals(2));
      final names = report.issues.map((i) => i.packageName).toList();
      expect(names, contains('remove_single'));
      expect(names, contains('remove_multiline'));

      final cleaner = DependencyCleaner(workspaceRoot: tempDir);
      final cleanResult = cleaner.clean(issues: report.issues);

      expect(cleanResult.removedCount, equals(2));
      expect(cleanResult.updatedPubspecsCount, equals(1));
      expect(cleanResult.backupManifest, isNotNull);

      // Verify that the lines were surgically removed from pubspec.yaml
      final updatedLines = pubFile.readAsLinesSync();
      expect(updatedLines.any((l) => l.contains('remove_single')), isFalse);
      expect(updatedLines.any((l) => l.contains('remove_multiline')), isFalse);
      expect(
          updatedLines
              .any((l) => l.contains('https://github.com/example/repo.git')),
          isFalse);

      // Verify that kept dependencies remain intact
      expect(updatedLines.any((l) => l.contains('keep_me: ^1.0.0')), isTrue);
      expect(updatedLines.any((l) => l.contains('also_keep: ^3.0.0')), isTrue);
    });
  });
}
