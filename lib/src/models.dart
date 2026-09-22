class CommentBlockItem {
  final int line;
  final String text;
  final bool isCode;

  CommentBlockItem({
    required this.line,
    required this.text,
    required this.isCode,
  });
}

class CommentBlockResult {
  final int startLine;
  final int endLine;
  final int totalLines;
  final int codeLines;
  final String sample;

  CommentBlockResult({
    required this.startLine,
    required this.endLine,
    required this.totalLines,
    required this.codeLines,
    required this.sample,
  });

  Map<String, dynamic> toJson() => {
        'startLine': startLine,
        'endLine': endLine,
        'totalLines': totalLines,
        'codeLines': codeLines,
        'sample': sample,
      };
}

class CommentedFileResult {
  final String file;
  final String absolutePath;
  final String fileUri;
  final int totalNonEmptyLines;
  final int commentLinesCount;
  final int commentRatio;
  final bool isFullyCommented;
  final bool isHighCommentRatio;
  final List<String> commentedClasses;
  final List<CommentBlockResult> blocks;

  CommentedFileResult({
    required this.file,
    required this.absolutePath,
    required this.fileUri,
    required this.totalNonEmptyLines,
    required this.commentLinesCount,
    required this.commentRatio,
    required this.isFullyCommented,
    required this.isHighCommentRatio,
    required this.commentedClasses,
    required this.blocks,
  });

  Map<String, dynamic> toJson() => {
        'file': file,
        'absolutePath': absolutePath,
        'fileUri': fileUri,
        'totalNonEmptyLines': totalNonEmptyLines,
        'commentLinesCount': commentLinesCount,
        'commentRatio': commentRatio,
        'isFullyCommented': isFullyCommented,
        'isHighCommentRatio': isHighCommentRatio,
        'commentedClasses': commentedClasses,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };
}

class DeclaredClassItem {
  final String name;
  final String file;
  final int line;
  final String category;
  final bool isPrivate;
  final String relPath;
  final String fileUri;

  DeclaredClassItem({
    required this.name,
    required this.file,
    required this.line,
    required this.category,
    required this.isPrivate,
    required this.relPath,
    required this.fileUri,
  });
}

class UnusedClassResult {
  final String name;
  final String file;
  final String relPath;
  final String fileUri;
  final int line;
  final String category;
  final bool isPrivate;
  final String type;
  final String severity;
  final String reason;
  final int internalMatches;
  final int externalMatches;

  UnusedClassResult({
    required this.name,
    required this.file,
    required this.relPath,
    required this.fileUri,
    required this.line,
    required this.category,
    required this.isPrivate,
    required this.type,
    required this.severity,
    required this.reason,
    required this.internalMatches,
    required this.externalMatches,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'file': file,
        'relPath': relPath,
        'fileUri': fileUri,
        'line': line,
        'category': category,
        'isPrivate': isPrivate,
        'type': type,
        'severity': severity,
        'reason': reason,
        'internalMatches': internalMatches,
        'externalMatches': externalMatches,
      };
}

class AnalysisReport {
  final String targetPath;
  final int totalTargetDartFiles;
  final int totalProjectDartFiles;
  final List<CommentedFileResult> fullyCommentedFiles;
  final List<CommentedFileResult> highRatioFiles;
  final List<CommentedFileResult> filesWithCommentBlocks;
  final List<UnusedClassResult> deadClasses;
  final List<UnusedClassResult> internalOnlyClasses;

  AnalysisReport({
    required this.targetPath,
    required this.totalTargetDartFiles,
    required this.totalProjectDartFiles,
    required this.fullyCommentedFiles,
    required this.highRatioFiles,
    required this.filesWithCommentBlocks,
    required this.deadClasses,
    required this.internalOnlyClasses,
  });

  Map<String, dynamic> toJson({bool includeInternal = false}) => {
        'summary': {
          'targetPath': targetPath.isEmpty ? '.' : targetPath,
          'totalTargetDartFiles': totalTargetDartFiles,
          'totalProjectDartFiles': totalProjectDartFiles,
          'fullyCommentedFilesCount': fullyCommentedFiles.length,
          'highCommentRatioFilesCount': highRatioFiles.length,
          'filesWithCommentBlocksCount': filesWithCommentBlocks.length,
          'deadClassesCount': deadClasses.length,
          'internalOnlyClassesCount': internalOnlyClasses.length,
        },
        'commentedFiles': {
          'fullyCommented': fullyCommentedFiles.map((f) => f.toJson()).toList(),
          'highRatio': highRatioFiles.map((f) => f.toJson()).toList(),
          'largeBlocks': filesWithCommentBlocks.map((f) => f.toJson()).toList(),
        },
        'unusedClasses': {
          'deadClasses': deadClasses.map((c) => c.toJson()).toList(),
          if (includeInternal)
            'internalOnly': internalOnlyClasses.map((c) => c.toJson()).toList(),
        },
      };
}

class AuditorOptions {
  final String? targetPath;
  final bool runClassAnalysis;
  final bool runCommentAnalysis;
  final bool includeInternal;
  final int commentThreshold;
  final int minBlockLines;
  final bool verbose;

  const AuditorOptions({
    this.targetPath,
    this.runClassAnalysis = true,
    this.runCommentAnalysis = true,
    this.includeInternal = false,
    this.commentThreshold = 60,
    this.minBlockLines = 15,
    this.verbose = false,
  });
}
