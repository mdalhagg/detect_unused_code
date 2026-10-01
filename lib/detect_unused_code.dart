/// detect_unused_code
///
/// A fast, zero-dependency Dart and Flutter dead code & unused code detector.
/// Detects unused classes, widgets, mixins, enums, commented-out files, and dead code blocks.
library detect_unused_code;

export 'src/auditor.dart' show UnusedCodeAuditor, AuditorProgressCallback;
export 'src/cli_runner.dart' show CliRunner;
export 'src/models.dart'
    show
        AuditorOptions,
        AnalysisReport,
        UnusedClassResult,
        CommentedFileResult,
        CommentBlockResult,
        DeclaredClassItem,
        TodoItemResult,
        DiagnosticIssueResult;
export 'src/utils.dart'
    show findProjectOrWorkspaceRoot, resolveTargetPath, walkDartFiles;
