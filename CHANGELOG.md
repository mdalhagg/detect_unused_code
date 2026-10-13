## 3.0.1

- **Interactive TUI Dashboard by Default:**
  - Launching `detect_unused` or `detect_unused_code` without command-line arguments now automatically opens the Interactive Terminal UI (TUI) Dashboard.
  - Added `--scan` and `--report` flags for running the standard non-interactive terminal audit report.
- **pubspec.yaml Description Optimization:**
  - Optimized package description length to comply strictly with pub.dev guidelines (60 to 180 characters), securing a full 160/160 pub points score.

## 3.0.0

- **Interactive Terminal UI (TUI) Dashboard (`--interactive` / `-i`):**
  - Automatically launches by default when executing `detect_unused` or `detect_unused_code` without command-line flags (use `--scan` or `--report` for non-interactive output).
  - Rich interactive terminal control panel wizard featuring zero external dependencies.
  - Interactive selection and toggles for 8 cleanable categories:
    - Dead Classes & Widgets
    - Dead Commented Code Blocks
    - 100% Commented Files
    - File-Internal Class Privatization
    - TODO Pending Tasks
    - Unused & Redundant Imports
    - Unused Media Assets & Fonts
    - Unused & Duplicate Dependencies
  - Commands supported directly inside the dashboard:
    - `[1-8]` Toggle individual category checkboxes.
    - `[A]` Toggle All categories.
    - `[V]` View item details and breakdown of detected targets.
    - `[D]` Preview Dry-Run simulation without disk changes.
    - `[C]` Clean selected categories with automatic pre-modification backup snapshot.
    - `[U]` Instant Undo of the last action.
    - `[M]` Export Markdown report to disk.
    - `[Q]` Quit dashboard.
  - Attribution banner: `⚡ Powered by @mdalhagg | https://github.com/mdalhagg`.
- **Instant Single-Step Rollback (`--undo` / `undo`):**
  - Instant rollback command restoring project files from the most recent backup snapshot in `.detect_unused/backups/`.
  - Automatically cleans up the snapshot after restoration unless `--keep-backup` is provided.
- **CI/CD GitHub Flavored Markdown (GFM) Report Generator (`--markdown` / `--report-md`):**
  - Generates comprehensive Markdown reports designed specifically for CI/CD pipelines and GitHub Actions `$GITHUB_STEP_SUMMARY`.
  - Summary metrics table with status badges (PASS / ATTENTION), collapsible `<details>` blocks for each issue category, and actionable CLI remediation suggestions.
  - Attribution and repository links in the report footer.
- **Automated Test Suite:**
  - Added test coverage in `test/interactive_and_reporting_test.dart` validating Markdown reporter generation and undo mechanisms.

## 2.4.0

- **Generated Code Auto-Exclusion Engine:**
  - Automatically identifies and excludes auto-generated source files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `*.config.dart`, `*.gr.dart`, `*.gen.dart`, `*.drift.dart`, `*.reflectable.dart`, etc.) from dead code auditing, diagnostic reports, and automated cleanup.
  - Maintains full reference resolution: generated files continue to be indexed for references so that original models (e.g., `User` used in `user.g.dart`) are correctly recognized as active.
  - Hardened `CodeCleaner` security guard: strictly prevents modifying or deleting any generated file under any cleanup flag.
- **Directives & Annotation Preservation Engine:**
  - Added support for class-level preservation directives: `// @keepUnused`, `/// @keepUnused`, `// keep-unused`, `// ignore: unused_code`, and `@keepUnused` annotations.
  - Added support for file-level preservation directives: `// ignore_for_file: unused_code` and `// @keepUnusedFile`.
  - Preserved elements are safely bypassed from dead class reports, internal privatizations, and cleaner deletions.
- **Dependency Injection (DI) & Framework Guards:**
  - Automatically protects classes decorated with Dependency Injection, Service Locator, or modular annotations (`@injectable`, `@singleton`, `@lazySingleton`, `@module`, `@named`, `@factoryMethod`, `@riverpod`, `@entrypoint`, `@pragma`).
  - Eliminates false-positives for services and repositories that are constructed indirectly via DI code generation or locator registries.
- **CLI Options & Tuning:**
  - Added `--exclude-generated` (enabled by default) and `--include-generated` to control generated file auditing.
  - Added `--no-di-guards` to disable DI pattern protection when desired.
  - Added `--exclude=<patterns>` to specify custom file exclusions or glob patterns.
- **Automated Test Suite:**
  - Added comprehensive automated unit and integration tests under `test/code_precision_test.dart` (100% passing).

## 2.3.0

- **External Package Dependencies Auditing Engine (`--packages` / `--audit-packages`):**
  - Added full detection of unused runtime (`dependencies:`) and development (`dev_dependencies:`) packages declared in `pubspec.yaml` but never imported or referenced in Dart source code.
  - Isolated per-package scoping: each `pubspec.yaml` across monorepos and nested sub-packages is evaluated strictly against its own package code scope, preventing false negatives where an import in a sub-package excuses an unused dependency in the root.
  - Zero false-positives guard: protects core SDK frameworks (`flutter`, `flutter_test`, `flutter_localizations`), CLI tools, linters (`lints`, `flutter_lints`, `custom_lint`), code generators and builders (`build_runner`, `json_serializable`, `freezed`, etc.), and `build.yaml` configurations.
- **Duplicate Dependency Detection:**
  - Automatically identifies duplicate package declarations within the same `pubspec.yaml` (duplicate entries under `dependencies:` or duplicated across both `dependencies:` and `dev_dependencies:`).
- **Safe Surgical Dependency Pruning (`--clean-packages`):**
  - Dedicated dependency cleaner with automatic pre-modification backup snapshot to `.detect_unused/backups/<id>/files/`.
  - Surgically removes both single-line (`pkg: ^1.0.0`) and multi-line (`git:`, `path:`, `hosted:`) dependency blocks from targeted `pubspec.yaml` files.
  - Preserves surrounding indentation, spacing, and comments.
  - Full instant rollback support via `detect_unused --restore <id>`.
  - Integrated into `--clean-all` as Step 9.
- **Automated Test Suite:**
  - Added comprehensive automated unit and integration tests under `test/dependency_auditor_test.dart` covering multi-pubspec scoping, duplicate detection, and surgical pruning.

## 2.2.0

- **Assets, Images & Fonts Auditing Engine (`--assets` / `--audit-assets`):**
  - Added full detection of unused media assets across Dart and Flutter projects, including raster images (PNG, JPG, WEBP, GIF), vectors (SVG), animations (Lottie JSON, Rive), and fonts (TTF, OTF).
  - Smart reference tracking supporting direct string paths, filenames, cross-package paths, and code-generator CamelCase identifiers (`flutter_gen` / `spider`).
  - Screen resolution variant awareness: preserves `2.0x/`, `3.0x/`, etc., whenever the parent/base image is used.
  - Font family tracking in `TextStyle(fontFamily: ...)` against `flutter -> fonts` in `pubspec.yaml`.
  - Calculates and reports exact reclaimable disk space in B, KB, MB, and GB.
- **Multi-Package & Monorepo Flexible Support:**
  - Flexible recursive discovery of all `pubspec.yaml` files located anywhere in the workspace (root, `packages/`, `modules/`, nested sub-packages, Melos monorepos).
  - Independent package context scoping (`PackageDescriptor`) mapping declared assets, fonts, and directory roots per package.
  - Cross-package reference resolution (`packages/<package_name>/assets/...`).
- **Safe Asset Pruning & Targeted Pubspec Updates (`--clean-assets`):**
  - Dedicated asset cleaner with automatic backup snapshots to `.detect_unused/backups/<id>/files/` before deletion.
  - Automatically prunes empty directories after deleting asset files.
  - Targeted surgical line pruning: removes explicit asset declarations from the specific owning `pubspec.yaml` without affecting other packages or YAML formatting.
  - Full rollback support via `detect_unused --restore <id>`.
  - Integrated into `--clean-all` as Step 8.
- **Automated Test Suite:**
  - Added comprehensive automated unit and integration tests covering multi-pubspec discovery, asset auditing, resolution variants, and cleaner rollback.

## 2.1.2

- Added automated GitHub Actions CI workflow (`.github/workflows/ci.yml`) verifying formatting, static analysis, and dry-run publishing on PRs and pushes.
- Added GitHub issue templates for bug reports and feature requests (`.github/ISSUE_TEMPLATE/`).
- Added open-source community standards guide (`CONTRIBUTING.md`).
- Added SEO-optimized FAQ section and repository status badges to `README.md`.
- Updated package version to `2.1.2`.

## 2.1.1

- Comprehensive documentation review and refinements across `README.md`.
- Updated recommended dependency declaration to `^2.1.1`.
- Added complete coverage for cleanup flags (`--clean-dead-code`, `--clean-backups`, `--keep-backup`, `--version`) in Arabic & English documentation.
- Improved clarity of safety architecture and step-by-step CLI usage examples.

## 2.1.0

- **Phased, Multi-Stage Cleanup Pipeline:**
  - Refactored `--clean-all` from a monolithic single-pass into a sequential 7-stage pipeline (Commented Files → Dead Classes → Dead Blocks → Internal Classes Privatization → TODOs → Unused Imports → Dead Code).
  - Automatically re-audits project AST and line offsets between each cleanup stage to guarantee 100% surgical accuracy and prevent offset drift.
  - Appends intermediate snapshot states incrementally into backup manifests.
- **Smart Dart Extension Member Awareness:**
  - Implemented deep AST inspection for Dart extensions, parsing declared getters, setters, methods, and static fields.
  - Extensions are now checked for cross-file member references, preventing false-positive "unused extension" flags when extension methods or properties are used without referencing the extension name explicitly.
- **Automated Constructor Key Cleanup in Privatized Classes:**
  - Automatically strips unused `super.key` and `Key? key` parameters and super initializers from constructors of privatized `_ClassName` widgets when no call sites pass `key:`, preventing `unused_element_parameter` analyzer warnings.
- **Enhanced Directive & File Boundary Parsing:**
  - Robust dangling URI directive cleanup handling single-line and multi-line `import`/`export`/`part` statements with exact URI matching.
  - String- and comment-aware block boundary scanner (`_findDeclarationEndLine`) that ignores braces inside single, double, triple-quoted strings and block comments.
  - Unbalanced comment marker check before removing dead blocks to safeguard file syntax integrity.
- **Windows Path & Character-by-Character Parser Robustness:**
  - Supported Windows 8.3 short paths resolution via symbolic link evaluation and sanitized drive prefixes.
  - Re-implemented `stripCommentsAndStrings` using a high-performance character-by-character scanner handling nested block comments, raw strings, and escapes while preserving exact line and column offsets.
- **CLI Flags & Target Scope Enhancements:**
  - Added `--version` and `-V` flags to quickly print the installed package version.
  - Added `--clean-backups` command to easily wipe all snapshot archives in `.detect_unused/backups/`.
  - Added `--keep-backup` flag to retain snapshot archives upon restore.
  - Automatic target project root resolution when passing a folder or file path argument.

## 2.0.1

- **Fix:** Exclude `.detect_unused/` and backup snapshot directories from file scanning and analysis to prevent scanning cached backups.
- **Improvement:** Automatically delete restored backup snapshot folders upon successful restoration to reclaim disk space (with `--keep-backup` flag to retain if desired).
- **Fix:** Auto-resolve dangling barrel export and import directives referencing deleted files during cleanup before running post-cleanup health verification.

## 2.0.0

- **Major Upgrade:** Transformed `detect_unused_code` into a powerful code remediation and automated cleaning engine while preserving zero external runtime dependencies.
- **Automated Cleanup Engine (`--clean-all`, `--clean`):**
  - Safely deletes 100% commented-out files (`--clean-commented-files`).
  - Surgically removes dead commented-out code blocks in active files (`--clean-dead-blocks`).
  - Removes zero-usage dead classes, mixins, widgets, and enums (`--clean-dead-classes`).
  - Safely privatizes file-internal only public classes to `_ClassName` (`--privatize-internal`).
  - Cleans and strips pending `// TODO` comment lines (`--clean-todos`).
  - Cleans `unused_import` and `unnecessary_import` statements (`--clean-unused-imports`).
  - Remediates dead null-aware expressions (`?.` to `.`) and unreachable dead code (`--clean-dead-code`).
- **Defensive Safety Architecture:**
  - **Snapshot Backups:** Automatically creates complete snapshots in `.detect_unused/backups/` before performing any cleanup.
  - **Instant Rollback:** Allows rolling back active project code to any previous snapshot with `detect_unused --restore <id>` or `detect_unused --restore-latest`.
  - **Backups Browser:** View all existing snapshots with `detect_unused --backups`.
  - **Automated `.gitignore` Protection:** Automatically adds `.detect_unused/` to `.gitignore` to prevent committing backup snapshots.
  - **Simulation Mode (`--dry-run`):** Preview planned file deletions and modifications without touching disk.
  - **Interactive Confirmation:** Prompts for explicit user confirmation before executing changes (bypassable with `--yes` or `-y`).
  - **Post-Cleanup Health Verification:** Automatically runs `dart analyze` after cleaning and prompts for an auto-rollback if any compiler errors are introduced.
- **Full API Documentation:** 100% dartdoc documentation coverage on all new classes (`BackupManager`, `BackupManifest`, `BackupFileEntry`, `RestoreResult`, `CodeCleaner`, `CleanResult`).

## 1.3.2

- Appended line number directly to the file path in the TODO console report (e.g. `path/to/file.dart:line`) enabling instant clickability in IDE terminals.

## 1.3.1

- Improved TODO comment scanner to capture all `TODO` tags across all comments, documentation comments (`///`), and inline notes, matching the Dart analyzer's `dart(todo)` diagnostic behavior in IDEs.

## 1.3.0

- Added comprehensive all-in-one default inspection covering 13 code quality points without requiring extra flags.
- Added Dart Analyzer diagnostics inspection:
  - `unused_import`: Unused imports across files.
  - `unnecessary_import`: Duplicate or redundant imports.
  - `unused_local_variable`: Unused local variables.
  - `unused_field`: Unused class fields.
  - `unused_element`: Unused private functions, methods, and elements.
  - `dead_code`: Unreachable dead code blocks.
  - `dead_null_aware_expression`: Unnecessary null-aware `?.` operators on non-nullable targets.
- Added TODO task tracker: Detects pending `// TODO: ...` and `/* TODO ... */` tasks with exact line numbers, descriptions, and clickable file URIs.
- Enabled file-internal only public classes analysis by default (`includeInternal: true`).
- Added fine-tuning flags: `--todos-only`, `--diagnostics-only`, `--no-todos`, `--no-diagnostics`, and `--no-internal`.
- Updated JSON report export (`--json`) to serialize all 13 inspection points and categorized diagnostics.
- Added `TodoItemResult` and `DiagnosticIssueResult` models with full dartdoc documentation.

## 1.2.0

- Added comprehensive dartdoc documentation comments across 100% of public API elements (classes, constructors, methods, and properties).
- Enclosed flow control statements in curly braces across all files to conform with `curly_braces_in_flow_control_structures` lint.
- Added `analysis_options.yaml` with `package:lints/recommended.yaml` and formatted all Dart files with `dart format`.

## 1.1.0

- Enhanced `--json` flag to automatically save the audit report as a `.json` file (`detect_unused_code.json`) in the current execution directory instead of printing raw JSON to the terminal.
- Added support for specifying a custom JSON output filename (e.g. `--json=custom_report.json` or `--json custom_report.json`).
- Added progress bar display during JSON analysis and a clean terminal summary showing the output file location upon completion.

## 1.0.0

- Initial release of `detect_unused_code`.
- Full project scan and path-specific scan (`--url`, `--path`, positional argument).
- Convenient short CLI command alias `detect_unused`.
- Detection of unused/dead classes, widgets, mixins, enums, controllers, and models.
- Detection of public classes with file-internal only usage (`--include-internal`).
- Detection of 100% commented-out files with extracted class names.
- Configurable thresholds for heavily commented files (`--threshold`).
- Configurable minimum line limits for commented code blocks (`--min-lines`).
- JSON output format support for CI/CD pipelines (`--json`).
- Zero external runtime dependencies.
- Programmatic API via `UnusedCodeAuditor`.
- Broad SDK compatibility (`>=2.17.0 <4.0.0`).
