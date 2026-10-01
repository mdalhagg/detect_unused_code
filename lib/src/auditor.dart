import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'utils.dart';

/// Callback signature for progress monitoring during an audit.
typedef AuditorProgressCallback = void Function(int percent, String message);

/// Primary auditor engine that scans Dart projects for dead code, unused classes, and commented files.
class UnusedCodeAuditor {
  /// The root directory of the project being audited.
  final Directory projectRoot;

  /// Configuration options for the audit run.
  final AuditorOptions options;

  /// Creates a new [UnusedCodeAuditor] for the specified [projectRoot] and [options].
  UnusedCodeAuditor({
    Directory? projectRoot,
    this.options = const AuditorOptions(),
  }) : projectRoot = projectRoot ?? findProjectOrWorkspaceRoot();

  /// Runs the full code analysis and returns an [AnalysisReport].
  AnalysisReport run({AuditorProgressCallback? onProgress}) {
    final targetEntity = resolveTargetPath(
      options.targetPath,
      projectRoot,
    );

    final allProjectFiles = walkDartFiles(projectRoot);
    final targetFiles = walkDartFiles(targetEntity);

    final runClassAnalysis = options.runClassAnalysis;
    final runCommentAnalysis = options.runCommentAnalysis;
    final runTodoAnalysis = options.runTodoAnalysis;
    final runDiagnostics = options.runDiagnostics;

    // 1. Build cache map (0% - 25%)
    final projectCleanMap = <String, String>{};
    if (runClassAnalysis) {
      final total = allProjectFiles.length;
      for (int i = 0; i < total; i++) {
        final f = allProjectFiles[i];
        try {
          final raw = f.readAsStringSync();
          projectCleanMap[canonicalizePath(f.path)] =
              stripCommentsAndStrings(raw);
        } catch (_) {}
        if (i % 15 == 0 || i == total - 1) {
          final p = (((i + 1) / (total == 0 ? 1 : total)) * 25).floor();
          onProgress?.call(p, 'Reading & indexing (${i + 1}/$total)');
        }
      }
    }

    // 2. Analyze commented code & TODO comments (25% - 50%)
    List<CommentedFileResult> commentedResults = [];
    if (runCommentAnalysis) {
      commentedResults = _analyzeCommentedCode(
        targetFiles,
        projectRoot.path,
        commentThreshold: options.commentThreshold,
        minBlockLines: options.minBlockLines,
        onFileProgress: (curr, total) {
          final p = 25 + (((curr / total) * 15).floor());
          onProgress?.call(p, 'Scanning comments ($curr/$total)');
        },
      );
    }

    List<TodoItemResult> todos = [];
    if (runTodoAnalysis) {
      todos = _scanTodos(
        targetFiles,
        projectRoot.path,
        onFileProgress: (curr, total) {
          final p = 40 + (((curr / total) * 10).floor());
          onProgress?.call(p, 'Scanning TODO tasks ($curr/$total)');
        },
      );
    }

    // 3. Analyze unused classes (50% - 75%)
    List<UnusedClassResult> unusedClassResults = [];
    if (runClassAnalysis) {
      unusedClassResults = _analyzeUnusedClasses(
        targetFiles,
        projectCleanMap,
        projectRoot.path,
        onFileProgress: (curr, total) {
          final p = 50 + (((curr / total) * 25).floor());
          onProgress?.call(p, 'Auditing classes ($curr/$total)');
        },
      );
    }

    // 4. Run Dart Analyzer diagnostics (75% - 95%)
    List<DiagnosticIssueResult> diagnostics = [];
    if (runDiagnostics) {
      onProgress?.call(80, 'Running Dart analyzer diagnostics...');
      diagnostics = _runDartAnalyzer(projectRoot, targetEntity);
      onProgress?.call(95, 'Dart analyzer completed');
    }

    onProgress?.call(100, 'Completed!');

    final fullyCommentedFiles =
        commentedResults.where((f) => f.isFullyCommented).toList();
    final highRatioFiles =
        commentedResults.where((f) => f.isHighCommentRatio).toList();
    final filesWithCommentBlocks = commentedResults
        .where((f) =>
            !f.isFullyCommented && !f.isHighCommentRatio && f.blocks.isNotEmpty)
        .toList();

    final deadClasses = unusedClassResults
        .where((c) =>
            c.type == 'PUBLIC_ZERO_EXTERNAL' || c.type == 'PRIVATE_UNUSED')
        .toList();
    final internalOnlyClasses = unusedClassResults
        .where((c) => c.type == 'FILE_INTERNAL_ONLY')
        .toList();

    final relTarget = getRelativePath(targetEntity.path, projectRoot.path);

    return AnalysisReport(
      targetPath: relTarget.isEmpty ? '.' : relTarget,
      totalTargetDartFiles: targetFiles.length,
      totalProjectDartFiles: allProjectFiles.length,
      fullyCommentedFiles: fullyCommentedFiles,
      highRatioFiles: highRatioFiles,
      filesWithCommentBlocks: filesWithCommentBlocks,
      deadClasses: deadClasses,
      internalOnlyClasses: internalOnlyClasses,
      todos: todos,
      diagnostics: diagnostics,
    );
  }

  List<CommentedFileResult> _analyzeCommentedCode(
    List<File> files,
    String rootPath, {
    required int commentThreshold,
    required int minBlockLines,
    void Function(int current, int total)? onFileProgress,
  }) {
    final results = <CommentedFileResult>[];
    final total = files.length;

    for (int fileIdx = 0; fileIdx < total; fileIdx++) {
      final file = files[fileIdx];
      if (onFileProgress != null &&
          (fileIdx % 10 == 0 || fileIdx == total - 1)) {
        onFileProgress(fileIdx + 1, total);
      }
      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));
      int totalNonEmpty = 0;
      int commentLinesCount = 0;
      bool inBlockComment = false;
      List<CommentBlockItem> currentBlock = [];
      final detectedBlocks = <CommentBlockResult>[];

      for (int i = 0; i < lines.length; i++) {
        final lineNum = i + 1;
        final trimmed = lines[i].trim();
        final isEmpty = trimmed.isEmpty;

        if (!isEmpty) totalNonEmpty++;

        bool isComment = false;
        bool isCodeComment = false;

        if (inBlockComment) {
          isComment = true;
          if (isDartCodeLine(trimmed)) isCodeComment = true;
          if (trimmed.contains('*/')) inBlockComment = false;
        } else if (trimmed.startsWith('/*')) {
          isComment = true;
          if (isDartCodeLine(trimmed)) isCodeComment = true;
          if (!trimmed.contains('*/') ||
              trimmed.indexOf('*/') < trimmed.indexOf('/*') + 2) {
            inBlockComment = true;
          }
        } else if (trimmed.startsWith('//')) {
          isComment = true;
          final body = trimmed.replaceFirst(RegExp(r'^///?\s*'), '');
          if (isDartCodeLine(body)) isCodeComment = true;
        }

        if (isComment) {
          if (!isEmpty) commentLinesCount++;
          currentBlock.add(CommentBlockItem(
              line: lineNum, text: trimmed, isCode: isCodeComment));
        } else {
          if (currentBlock.length >= minBlockLines) {
            final codeLines = currentBlock.where((b) => b.isCode).length;
            if (codeLines >= 3 || codeLines / currentBlock.length >= 0.2) {
              detectedBlocks.add(CommentBlockResult(
                startLine: currentBlock.first.line,
                endLine: currentBlock.last.line,
                totalLines: currentBlock.length,
                codeLines: codeLines,
                sample: currentBlock.take(3).map((b) => b.text).join('\n'),
              ));
            }
          }
          currentBlock = [];
        }
      }

      if (currentBlock.length >= minBlockLines) {
        final codeLines = currentBlock.where((b) => b.isCode).length;
        if (codeLines >= 3 || codeLines / currentBlock.length >= 0.2) {
          detectedBlocks.add(CommentBlockResult(
            startLine: currentBlock.first.line,
            endLine: currentBlock.last.line,
            totalLines: currentBlock.length,
            codeLines: codeLines,
            sample: currentBlock.take(3).map((b) => b.text).join('\n'),
          ));
        }
      }

      if (totalNonEmpty == 0) continue;

      final commentRatio =
          ((commentLinesCount / totalNonEmpty) * 100).round().clamp(0, 100);
      final isFullyCommented = commentRatio >= 90 && totalNonEmpty >= 8;
      final isHighCommentRatio = !isFullyCommented &&
          commentRatio >= commentThreshold &&
          totalNonEmpty >= 15;

      if (isFullyCommented || isHighCommentRatio || detectedBlocks.isNotEmpty) {
        final relPath = getRelativePath(file.path, rootPath);
        final commentedClasses =
            isFullyCommented ? extractCommentedClasses(content) : <String>[];

        results.add(CommentedFileResult(
          file: relPath,
          absolutePath: file.path,
          fileUri: toFileUri(file.path),
          totalNonEmptyLines: totalNonEmpty,
          commentLinesCount: commentLinesCount,
          commentRatio: commentRatio,
          isFullyCommented: isFullyCommented,
          isHighCommentRatio: isHighCommentRatio,
          commentedClasses: commentedClasses,
          blocks: detectedBlocks,
        ));
      }
    }

    return results;
  }

  List<UnusedClassResult> _analyzeUnusedClasses(
    List<File> filesToScan,
    Map<String, String> projectCleanMap,
    String rootPath, {
    void Function(int current, int total)? onFileProgress,
  }) {
    final declaredClasses = <DeclaredClassItem>[];

    final classDeclRegex = RegExp(
      r'\b(?:(abstract\s+|base\s+|sealed\s+|interface\s+|final\s+)?class|(enum)|(mixin)|(extension\s+type)|(extension))\s+([A-Za-z0-9_$]+)',
    );

    for (final file in filesToScan) {
      final cleanContent = projectCleanMap[canonicalizePath(file.path)];
      if (cleanContent == null) continue;

      final lines = cleanContent.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final match in classDeclRegex.allMatches(line)) {
          final className = match.group(6);
          if (className == null || className.length < 2) continue;

          final isEnum = match.group(2) != null;
          final isMixin = match.group(3) != null;
          final isExtension = match.group(4) != null || match.group(5) != null;

          String category = 'Class';
          if (isEnum) {
            category = 'Enum';
          } else if (isMixin) {
            category = 'Mixin';
          } else if (isExtension) {
            category = 'Extension';
          } else if (line.contains('Controller') ||
              className.endsWith('Controller')) {
            category = 'Controller';
          } else if (line.contains('Widget') ||
              line.contains('State<') ||
              className.endsWith('Page') ||
              className.endsWith('View') ||
              className.endsWith('Widget') ||
              className.endsWith('Screen')) {
            category = 'Widget/Page';
          } else if (line.contains('Entity') ||
              className.endsWith('Entity') ||
              className.endsWith('Model') ||
              className.endsWith('Response') ||
              className.endsWith('Request')) {
            category = 'Entity/Model';
          } else if (className.endsWith('Repository') ||
              className.endsWith('Service')) {
            category = 'Service/Repository';
          }

          declaredClasses.add(DeclaredClassItem(
            name: className,
            file: file.path,
            line: i + 1,
            category: category,
            isPrivate: className.startsWith('_'),
            relPath: getRelativePath(file.path, rootPath),
            fileUri: toFileUri(file.path),
          ));
        }
      }
    }

    final results = <UnusedClassResult>[];
    final totalDeclared = declaredClasses.length;

    for (int i = 0; i < totalDeclared; i++) {
      final item = declaredClasses[i];
      if (onFileProgress != null && (i % 3 == 0 || i == totalDeclared - 1)) {
        onFileProgress(i + 1, totalDeclared);
      }
      final wordRegex = RegExp('\\b${RegExp.escape(item.name)}\\b');

      int totalExternalMatches = 0;
      final itemCanon = canonicalizePath(item.file);

      for (final entry in projectCleanMap.entries) {
        if (entry.key != itemCanon) {
          final matchesCount = wordRegex.allMatches(entry.value).length;
          if (matchesCount > 0) {
            totalExternalMatches += matchesCount;
          }
        }
      }

      if (totalExternalMatches == 0) {
        final fileCleanCode = projectCleanMap[itemCanon] ?? '';
        final internalUsages = countInternalUsages(fileCleanCode, item.name);

        if (internalUsages == 0) {
          results.add(UnusedClassResult(
            name: item.name,
            file: item.file,
            relPath: item.relPath,
            fileUri: item.fileUri,
            line: item.line,
            category: item.category,
            isPrivate: item.isPrivate,
            type: item.isPrivate ? 'PRIVATE_UNUSED' : 'PUBLIC_ZERO_EXTERNAL',
            severity: 'CRITICAL',
            reason: item.isPrivate
                ? 'Private class unused even within declaring file'
                : 'Public class (${item.category}) with zero usages across project or file',
            internalMatches: 0,
            externalMatches: 0,
          ));
        } else {
          if (!item.isPrivate) {
            results.add(UnusedClassResult(
              name: item.name,
              file: item.file,
              relPath: item.relPath,
              fileUri: item.fileUri,
              line: item.line,
              category: item.category,
              isPrivate: false,
              type: 'FILE_INTERNAL_ONLY',
              severity: 'MEDIUM',
              reason:
                  'Public class used file-internally only ($internalUsages local usages)',
              internalMatches: internalUsages,
              externalMatches: 0,
            ));
          }
        }
      }
    }

    return results;
  }

  List<TodoItemResult> _scanTodos(
    List<File> files,
    String rootPath, {
    void Function(int current, int total)? onFileProgress,
  }) {
    final todos = <TodoItemResult>[];
    final total = files.length;

    for (int fileIdx = 0; fileIdx < total; fileIdx++) {
      final file = files[fileIdx];
      if (onFileProgress != null &&
          (fileIdx % 10 == 0 || fileIdx == total - 1)) {
        onFileProgress(fileIdx + 1, total);
      }
      String content;
      try {
        content = file.readAsStringSync();
      } catch (_) {
        continue;
      }

      final lines = content.split(RegExp(r'\r?\n'));
      bool inBlockComment = false;
      bool inTripleSingle = false;
      bool inTripleDouble = false;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();
        final lineNum = i + 1;

        if (!inBlockComment) {
          final countTripleSingle = "'''".allMatches(line).length;
          if (countTripleSingle % 2 != 0) {
            inTripleSingle = !inTripleSingle;
          }
          final countTripleDouble = '"""'.allMatches(line).length;
          if (countTripleDouble % 2 != 0) {
            inTripleDouble = !inTripleDouble;
          }
        }

        if (inTripleSingle || inTripleDouble) {
          continue;
        }

        String? commentText;
        int commentOffset = 0;

        if (inBlockComment) {
          commentText = line;
          commentOffset = 0;
          if (trimmed.contains('*/')) {
            inBlockComment = false;
          }
        } else if (trimmed.startsWith('/*')) {
          commentText = line;
          commentOffset = 0;
          if (!trimmed.contains('*/') ||
              trimmed.indexOf('*/') < trimmed.indexOf('/*') + 2) {
            inBlockComment = true;
          }
        } else if (line.contains('//')) {
          final idx = line.indexOf('//');
          final before = line.substring(0, idx);
          final singleQuotes = "'".allMatches(before).length;
          final doubleQuotes = '"'.allMatches(before).length;
          if (singleQuotes % 2 == 0 && doubleQuotes % 2 == 0) {
            commentText = line.substring(idx + 2);
            commentOffset = idx + 2;
          }
        }

        if (commentText != null) {
          final match = RegExp(r'\bTODO\b:?\s*(.*)', caseSensitive: false)
              .firstMatch(commentText);
          if (match != null) {
            var msg = match.group(0)?.trim() ?? '';
            if (msg.endsWith('*/')) {
              msg = msg.substring(0, msg.length - 2).trim();
            }
            if (msg.isEmpty) {
              msg = 'TODO';
            }
            final col = commentOffset + match.start + 1;
            final relPath = getRelativePath(file.path, rootPath);
            todos.add(TodoItemResult(
              file: relPath,
              absolutePath: file.path,
              fileUri: toFileUri(file.path, line: lineNum, column: col),
              line: lineNum,
              message: msg,
              rawLine: line.trim(),
            ));
          }
        }
      }
    }
    return todos;
  }

  List<DiagnosticIssueResult> _runDartAnalyzer(
    Directory projectRoot,
    FileSystemEntity targetEntity,
  ) {
    try {
      final targetPath = targetEntity.path;
      final result = Process.runSync(
        'dart',
        ['analyze', '--format=json', targetPath],
        workingDirectory: projectRoot.path,
        runInShell: true,
      );

      final stdoutStr = result.stdout as String? ?? '';
      if (stdoutStr.trim().isEmpty) {
        return [];
      }

      final jsonStart = stdoutStr.indexOf('{');
      final jsonEnd = stdoutStr.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd < jsonStart) {
        return [];
      }

      final jsonContent = stdoutStr.substring(jsonStart, jsonEnd + 1);
      final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
      final diagnosticsJson = decoded['diagnostics'] as List<dynamic>? ?? [];

      const targetCodes = {
        'unused_local_variable',
        'unused_element',
        'dead_null_aware_expression',
        'unused_import',
        'dead_code',
        'unused_field',
        'unnecessary_import',
      };

      final results = <DiagnosticIssueResult>[];
      for (final item in diagnosticsJson) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final rawCode = (item['code'] ?? '').toString().toLowerCase();
        if (!targetCodes.contains(rawCode)) {
          continue;
        }

        final message = (item['problemMessage'] ?? '').toString();
        final correction = item['correctionMessage']?.toString();
        final severity = (item['severity'] ?? 'INFO').toString();

        final location = item['location'] as Map<String, dynamic>?;
        final filePath = (location?['file'] ?? '').toString();
        final range = location?['range'] as Map<String, dynamic>?;
        final start = range?['start'] as Map<String, dynamic>?;
        final line = (start?['line'] as num?)?.toInt() ?? 1;
        final column = (start?['column'] as num?)?.toInt() ?? 1;

        final relPath = getRelativePath(filePath, projectRoot.path);
        final fileUri = toFileUri(filePath, line: line, column: column);

        results.add(DiagnosticIssueResult(
          code: rawCode,
          message: message,
          correction: correction,
          file: relPath,
          absolutePath: filePath,
          fileUri: fileUri,
          line: line,
          column: column,
          severity: severity,
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }
}
