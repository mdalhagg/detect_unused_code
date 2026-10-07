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
