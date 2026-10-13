/// detect_unused_code
///
/// A fast, zero-dependency Dart and Flutter dead code & unused code detector and remediation engine.
/// Detects and cleans unused classes, widgets, mixins, enums, commented-out files, dead code blocks,
/// unused imports, variables, fields, and pending TODOs with automatic backups and rollbacks.
library detect_unused_code;

export 'src/auditor.dart' show UnusedCodeAuditor, AuditorProgressCallback;
export 'src/backup/backup_manager.dart' show BackupManager, RestoreResult;
export 'src/backup/backup_manifest.dart' show BackupManifest, BackupFileEntry;
export 'src/cleaners/code_cleaner.dart'
    show
        CodeCleaner,
        CleanResult,
        HealthIssue,
        HealthCheckResult,
        RemovedDirectiveItem;
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
    show
        findProjectOrWorkspaceRoot,
        resolveTargetPath,
        walkDartFiles,
        isGeneratedDartFile,
        hasKeepUnusedDirective,
        hasFileKeepUnusedDirective,
        hasDependencyInjectionAnnotation;
export 'src/assets/asset_models.dart'
    show
        AssetCategory,
        PackageDescriptor,
        UnusedAssetItem,
        AssetAnalysisReport,
        formatByteSize;
export 'src/assets/pubspec_scanner.dart' show PubspecScanner;
export 'src/assets/asset_auditor.dart' show AssetAuditor, AssetProgressCallback;
export 'src/cleaners/asset_cleaner.dart' show AssetCleaner, CleanAssetsResult;
export 'src/packages/package_dep_models.dart'
    show
        DependencyScope,
        DependencyIssueType,
        DeclaredDependency,
        UnusedDependencyItem,
        PackageDependenciesReport;
export 'src/packages/dep_auditor.dart'
    show DependencyAuditor, DepProgressCallback;
export 'src/cleaners/dep_cleaner.dart'
    show DependencyCleaner, CleanDependenciesResult;
export 'src/version.dart' show packageVersion;
