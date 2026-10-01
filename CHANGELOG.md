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
