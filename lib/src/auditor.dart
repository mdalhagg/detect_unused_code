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

    // 1. Build cache map (0% - 40%)
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
          final p = runCommentAnalysis
              ? (((i + 1) / (total == 0 ? 1 : total)) * 40).floor()
              : (((i + 1) / (total == 0 ? 1 : total)) * 45).floor();
          onProgress?.call(p, 'Reading & indexing (${i + 1}/$total)');
        }
      }
    }

    // 2. Analyze commented code (40% - 50%)
    List<CommentedFileResult> commentedResults = [];
    if (runCommentAnalysis) {
      commentedResults = _analyzeCommentedCode(
        targetFiles,
        projectRoot.path,
        commentThreshold: options.commentThreshold,
        minBlockLines: options.minBlockLines,
        onFileProgress: (curr, total) {
          final p = runClassAnalysis
              ? 40 + (((curr / total) * 10).floor())
              : ((curr / total) * 100).floor();
          onProgress?.call(p, 'Scanning comments ($curr/$total)');
        },
      );
    }

    // 3. Analyze unused classes (50% - 100%)
    List<UnusedClassResult> unusedClassResults = [];
    if (runClassAnalysis) {
      unusedClassResults = _analyzeUnusedClasses(
        targetFiles,
        projectCleanMap,
        projectRoot.path,
        onFileProgress: (curr, total) {
          final p = runCommentAnalysis
              ? 50 + (((curr / total) * 50).floor())
              : 45 + (((curr / total) * 55).floor());
          onProgress?.call(p, 'Auditing classes ($curr/$total)');
        },
      );
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
}
