/// Internal representation of a single commented line during analysis.
class CommentBlockItem {
  /// The 1-based line number in the source file.
  final int line;

  /// The raw text of the commented line.
  final String text;

  /// Whether the commented line contains Dart code syntax.
  final bool isCode;

  /// Creates a new [CommentBlockItem].
  CommentBlockItem({
    required this.line,
    required this.text,
    required this.isCode,
  });
}

/// Represents a detected continuous block of commented-out code.
class CommentBlockResult {
  /// Starting line number (1-based) of the commented block.
  final int startLine;

  /// Ending line number (1-based) of the commented block.
  final int endLine;

  /// Total number of lines in this commented block.
  final int totalLines;

  /// Number of lines in this block that contain recognizable Dart code syntax.
  final int codeLines;

  /// Sample preview text of the commented block.
  final String sample;

  /// Creates a new [CommentBlockResult].
  CommentBlockResult({
    required this.startLine,
    required this.endLine,
    required this.totalLines,
    required this.codeLines,
    required this.sample,
  });

  /// Serializes the comment block result into a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'startLine': startLine,
        'endLine': endLine,
        'totalLines': totalLines,
        'codeLines': codeLines,
        'sample': sample,
      };
}

/// Represents the analysis result of a file with significant commented-out content.
class CommentedFileResult {
  /// Relative file path from the project root.
  final String file;

  /// Absolute system path to the file.
  final String absolutePath;

  /// Clickable `file://` URI string for IDE navigation.
  final String fileUri;

  /// Total count of non-empty lines in the file.
  final int totalNonEmptyLines;

  /// Count of comment lines found in the file.
  final int commentLinesCount;

  /// Percentage ratio (0-100) of comment lines to total non-empty lines.
  final int commentRatio;

  /// Whether the file is almost entirely commented out (>= 90%).
  final bool isFullyCommented;

  /// Whether the file exceeds the configured comment threshold.
  final bool isHighCommentRatio;

  /// Names of classes/enums found commented-out inside this file.
  final List<String> commentedClasses;

  /// List of large dead code blocks detected within this file.
  final List<CommentBlockResult> blocks;

  /// Creates a new [CommentedFileResult].
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

  /// Serializes the commented file result into a JSON-compatible map.
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

/// Metadata describing a declared class, enum, mixin, or extension in a Dart file.
class DeclaredClassItem {
  /// The declared identifier name.
  final String name;

  /// Absolute file path where the declaration resides.
  final String file;

  /// 1-based line number of the declaration.
  final int line;

  /// Architectural category (e.g., Widget/Page, Controller, Model, etc.).
  final String category;

  /// Whether the identifier is private (starts with `_`).
  final bool isPrivate;

  /// Relative file path from the project root.
  final String relPath;

  /// Clickable `file://` URI string for IDE navigation.
  final String fileUri;

  /// Creates a new [DeclaredClassItem].
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

/// Represents the audit finding for an unused or dead class.
class UnusedClassResult {
  /// The declared class or element name.
  final String name;

  /// Absolute file path where the class is declared.
  final String file;

  /// Relative file path from the project root.
  final String relPath;

  /// Clickable `file://` URI string for IDE navigation.
  final String fileUri;

  /// 1-based line number of the declaration.
  final int line;

  /// Architectural category (e.g., Widget/Page, Controller, Service).
  final String category;

  /// Whether the class is private (starts with `_`).
  final bool isPrivate;

  /// Classification type (e.g. `PUBLIC_ZERO_EXTERNAL`, `FILE_INTERNAL_ONLY`).
  final String type;

  /// Severity level (e.g. `CRITICAL`, `MEDIUM`).
  final String severity;

  /// Human-readable explanation of why this class was flagged.
  final String reason;

  /// Number of references found within the declaring file itself.
  final int internalMatches;

  /// Number of references found in external project files.
  final int externalMatches;

  /// Creates a new [UnusedClassResult].
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

  /// Serializes the unused class result into a JSON-compatible map.
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

/// Comprehensive report containing all findings from an audit run.
class AnalysisReport {
  /// The target directory or file path analyzed.
  final String targetPath;

  /// Total count of Dart files in the target scope.
  final int totalTargetDartFiles;

  /// Total count of Dart files across the entire project.
  final int totalProjectDartFiles;

  /// Files that are 90%+ commented out.
  final List<CommentedFileResult> fullyCommentedFiles;

  /// Files with high comment ratios exceeding the threshold.
  final List<CommentedFileResult> highRatioFiles;

  /// Active files that contain large blocks of commented-out code.
  final List<CommentedFileResult> filesWithCommentBlocks;

  /// Classes with zero references project-wide.
  final List<UnusedClassResult> deadClasses;

  /// Public classes used only inside their declaring file.
  final List<UnusedClassResult> internalOnlyClasses;

  /// Creates a new [AnalysisReport].
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

  /// Serializes the full analysis report into a JSON-compatible map.
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

/// Configuration options for [UnusedCodeAuditor].
class AuditorOptions {
  /// Target path to scan (defaults to project root).
  final String? targetPath;

  /// Whether to run unused and dead classes analysis.
  final bool runClassAnalysis;

  /// Whether to run commented-out code and block analysis.
  final bool runCommentAnalysis;

  /// Whether to include file-internal only public classes in the report.
  final bool includeInternal;

  /// Comment ratio percentage (1-100) to flag a file as heavily commented.
  final int commentThreshold;

  /// Minimum consecutive lines of commented Dart code to flag a dead block.
  final int minBlockLines;

  /// Whether to enable verbose logging with snippet samples.
  final bool verbose;

  /// Creates a new [AuditorOptions] configuration.
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
