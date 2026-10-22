import 'dart:io';

import 'package:detect_unused_code/detect_unused_code.dart';
import 'package:test/test.dart';

void main() {
  group('Code Precision & Protection Engine Tests', () {
    test('Helper functions identify generated files accurately', () {
      expect(isGeneratedDartFile('lib/models/user.g.dart'), isTrue);
      expect(isGeneratedDartFile('lib/models/user.freezed.dart'), isTrue);
      expect(isGeneratedDartFile('lib/services/api.mocks.dart'), isTrue);
      expect(isGeneratedDartFile('lib/di/locator.config.dart'), isTrue);
      expect(isGeneratedDartFile('lib/router/app_router.gr.dart'), isTrue);
      expect(isGeneratedDartFile('lib/gen/assets.gen.dart'), isTrue);
      expect(isGeneratedDartFile('lib/data/db.drift.dart'), isTrue);

      expect(isGeneratedDartFile('lib/models/user.dart'), isFalse);
      expect(isGeneratedDartFile('lib/services/api_service.dart'), isFalse);
      expect(isGeneratedDartFile('lib/main.dart'), isFalse);
    });

    test('Helper functions identify @keepUnused directives and DI annotations',
        () {
      final lines = [
        'import "package:flutter/material.dart";',
        '',
        '// @keepUnused',
        'class PreservedWidget extends StatelessWidget {}',
        '',
        '@injectable',
        'class InjectedService {}',
        '',
        '@LazySingleton()',
        'class LazyService {}',
        '',
        '// ignore: unused_code',
        'class IgnoredClass {}',
        '',
        'class RegularDeadClass {}',
      ];

      expect(hasKeepUnusedDirective(lines, 3), isTrue); // PreservedWidget
      expect(hasDependencyInjectionAnnotation(lines, 6),
          isTrue); // InjectedService
      expect(hasDependencyInjectionAnnotation(lines, 9), isTrue); // LazyService
      expect(hasKeepUnusedDirective(lines, 12), isTrue); // IgnoredClass
      expect(hasKeepUnusedDirective(lines, 14), isFalse); // RegularDeadClass
      expect(hasDependencyInjectionAnnotation(lines, 14),
          isFalse); // RegularDeadClass
    });

    test('File-level directives correctly protect entire files', () {
      const fileWithIgnore = '''
// ignore_for_file: unused_code
import 'package:flutter/material.dart';

class Abandoned1 {}
class Abandoned2 {}
''';

      const fileWithKeepUnused = '''
// @keepUnusedFile
class Abandoned3 {}
''';

      const regularFile = '''
import 'package:flutter/material.dart';

class NormalClass {}
''';

      expect(hasFileKeepUnusedDirective(fileWithIgnore), isTrue);
      expect(hasFileKeepUnusedDirective(fileWithKeepUnused), isTrue);
      expect(hasFileKeepUnusedDirective(regularFile), isFalse);
    });

    test(
        'UnusedCodeAuditor respects generated file exclusions, directives, and DI guards',
        () {
      final tempDir =
          Directory.systemTemp.createTempSync('code_precision_test_');

      try {
        // Setup mock project
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: mock_precision_app
version: 1.0.0
environment:
  sdk: '>=2.17.0 <4.0.0'
''');

        final libDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);

        // 1. user.dart (User model used in user.g.dart, and PreservedModel with @keepUnused)
        File('${libDir.path}/user.dart').writeAsStringSync('''
class User {
  final String id;
  User(this.id);
}

// @keepUnused
class PreservedModel {
  final String note;
  PreservedModel(this.note);
}
''');

        // 2. user.g.dart (generated file that references User, and declares _$User)
        File('${libDir.path}/user.g.dart').writeAsStringSync('''
// GENERATED CODE - DO NOT MODIFY BY HAND
part of 'user.dart';

class _\$User {
  void serialize(User user) {
    print(user.id);
  }
}
''');

        // 3. auth_service.dart (annotated with @injectable)
        File('${libDir.path}/auth_service.dart').writeAsStringSync('''
@injectable
class AuthService {
  void login() {}
}
''');

        // 4. legacy_helper.dart (has file-level ignore)
        File('${libDir.path}/legacy_helper.dart').writeAsStringSync('''
// ignore_for_file: unused_code
class LegacyHelper {
  void doOldThing() {}
}
''');

        // 5. dead_component.dart (truly dead class with 0 usages)
        File('${libDir.path}/dead_component.dart').writeAsStringSync('''
class DeadComponent {
  void neverCalled() {}
}
''');

        // 6. main.dart (active app entry)
        File('${libDir.path}/main.dart').writeAsStringSync('''
void main() {
  print('Running mock app');
}
''');

        final auditor = UnusedCodeAuditor(
          projectRoot: tempDir,
          options: const AuditorOptions(
            runDiagnostics: false,
            runCommentAnalysis: false,
            runTodoAnalysis: false,
            excludeGenerated: true,
            protectDiClasses: true,
          ),
        );

        final report = auditor.run();

        final deadNames = report.deadClasses.map((c) => c.name).toSet();

        // DeadComponent MUST be flagged
        expect(deadNames, contains('DeadComponent'));

        // User is referenced in user.g.dart, so it must NOT be flagged
        expect(deadNames, isNot(contains('User')));

        // PreservedModel has // @keepUnused, so it must NOT be flagged
        expect(deadNames, isNot(contains('PreservedModel')));

        // AuthService has @injectable, so it must NOT be flagged
        expect(deadNames, isNot(contains('AuthService')));

        // LegacyHelper has // ignore_for_file: unused_code, so it must NOT be flagged
        expect(deadNames, isNot(contains('LegacyHelper')));

        // _$User declared inside generated user.g.dart must NOT be flagged
        expect(deadNames, isNot(contains('_\$User')));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('CodeCleaner guards against modifying or deleting generated files',
        () {
      final tempDir =
          Directory.systemTemp.createTempSync('cleaner_guard_test_');

      try {
        final libDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        final genFile = File('${libDir.path}/sample.g.dart')
          ..writeAsStringSync('''
// 100% commented-out or generated content
/*
class GeneratedOldDummy {}
*/
''');

        final cleaner = CodeCleaner(tempDir);

        // Attempting to delete commented files
        final res = cleaner.cleanCommentedFiles([
          CommentedFileResult(
            file: 'lib/sample.g.dart',
            absolutePath: genFile.path,
            fileUri: 'file://${genFile.path}',
            totalNonEmptyLines: 10,
            commentLinesCount: 10,
            commentRatio: 100,
            isFullyCommented: true,
            isHighCommentRatio: false,
            commentedClasses: ['GeneratedOldDummy'],
            blocks: const [],
          ),
        ], dryRun: false, createBackup: false);

        expect(res.deletedFiles, isEmpty);
        expect(genFile.existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'Comment auditor does not flag string literals containing comment delimiters',
        () {
      final tempDir =
          Directory.systemTemp.createTempSync('comment_string_test_');
      try {
        final libDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        File('${libDir.path}/sample.dart').writeAsStringSync(r"""
class SampleService {
  void checkPatterns(String trimmed) {
    final s1 = '/* not a comment */';
    final s2 = "/* also not a comment */";
    final s3 = r'/* raw string */';
    final s4 = trimmed.startsWith('/*');
    final s5 = "test/mocks/*";
    final multiline = '''
      line 1 with /* block */
      line 2 with // comment
    ''';
    print('$s1 $s2 $s3 $s4 $s5 $multiline');
  }

  void anotherMethod() {
    print("All this is active Dart code!");
  }
}
""");

        final auditor = UnusedCodeAuditor(
          projectRoot: tempDir,
          options: const AuditorOptions(
            runDiagnostics: false,
            runTodoAnalysis: false,
            runClassAnalysis: false,
            runCommentAnalysis: true,
          ),
        );
        final report = auditor.run();

        expect(report.filesWithCommentBlocks, isEmpty);
        expect(report.fullyCommentedFiles, isEmpty);
        expect(report.highRatioFiles, isEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Comment auditor still correctly detects real dead code blocks', () {
      final tempDir = Directory.systemTemp.createTempSync('real_comment_test_');
      try {
        final libDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        File('${libDir.path}/sample.dart').writeAsStringSync('''
class ActiveClass {
  void run() {}
}

/*
class DeadWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
*/
''');

        final auditor = UnusedCodeAuditor(
          projectRoot: tempDir,
          options: const AuditorOptions(
            minBlockLines: 3,
            runDiagnostics: false,
            runTodoAnalysis: false,
            runClassAnalysis: false,
            runCommentAnalysis: true,
          ),
        );
        final report = auditor.run();

        expect(report.filesWithCommentBlocks, isNotEmpty);
        expect(report.filesWithCommentBlocks.first.blocks, isNotEmpty);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
