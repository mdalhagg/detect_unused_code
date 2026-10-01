# detect_unused_code

[![pub package](https://img.shields.io/pub/v/detect_unused_code.svg)](https://pub.dev/packages/detect_unused_code)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D2.17.0%20%3C4.0.0-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

A static analysis tool and Dart library to detect dead classes, unused widgets, commented-out files, dead code blocks, unused imports, unused variables, and pending TODO tasks across Dart and Flutter projects.

Works with zero external dependencies, runs on any Dart SDK from `2.17.0` up to Dart `3.x` / `4.x`, and supports both CLI usage and programmatic Dart API.

---

## Why Is This Critical for Medium & Large Projects?

Standard `dart analyze` / `flutter analyze` is great for syntax and unused private fields, but **it cannot detect unused public classes, widgets, or models**. In Dart, public classes are considered potential library exports, so the compiler will never warn you if a public `Widget`, `Controller`, or `Model` is completely abandoned.

In growing codebases (50+ to 1,000+ files), technical debt accumulates fast:
- **Forgotten Widgets & Screens**: Refactored pages leave behind dialogs, input fields, and widgets that nothing references anymore.
- **100% Commented-Out Files**: Old implementations commented out with `/* ... */` during a quick fix and forgotten forever.
- **Dead Code Blocks**: Large chunks of abandoned logic (15+ lines) remaining inside active production files.
- **Orphaned Public Classes**: Helper classes used in only one file that should either be private (`_`) or deleted.
- **Accumulated Technical Debt**: Unused imports, dead variables, dead expressions, and forgotten `// TODO:` notes.

This tool solves that gap by scanning your entire workspace, cross-referencing declarations against active code, running comprehensive static analysis, and reporting exact file paths and line numbers in seconds.

---

## What It Audits (13 Code Quality Points)

Running `detect_unused_code` without any arguments automatically performs a comprehensive scan covering all 13 points:

1. **Unused & Dead Classes**: Declared classes, widgets, mixins, enums, extensions, and controllers that have 0 references across the entire workspace.
2. **File-Internal Only Public Classes**: Public classes that are only used inside their declaring file (candidates to become private `_` or to be deleted).
3. **Fully Commented-Out Files**: Files where 90%+ of the content is commented-out code (extracts the commented class names).
4. **Heavily Commented Files**: Active files exceeding a configurable comment percentage threshold (default: 60%).
5. **Large Dead Code Blocks**: Abandoned multi-line code blocks commented out inside active files (default: 15+ consecutive lines).
6. **TODO Comments & Pending Tasks**: Tracks pending `// TODO: ...` and `/* TODO ... */` tasks with exact line numbers and descriptions.
7. **Unused Imports (`unused_import`)**: Imports declared in a file that are never referenced.
8. **Unnecessary Imports (`unnecessary_import`)**: Redundant or duplicated imports.
9. **Unused Local Variables (`unused_local_variable`)**: Local variables initialized but never read.
10. **Unused Fields (`unused_field`)**: Private/internal class fields that are never accessed.
11. **Unused Elements (`unused_element`)**: Private functions, methods, or declarations that have zero calls.
12. **Dead Code (`dead_code`)**: Unreachable code blocks (e.g. following a return or break statement).
13. **Dead Null-Aware Expressions (`dead_null_aware_expression`)**: Unnecessary `?.` operators applied to non-nullable expressions.

---

## Example Audit Output

Here is what running the tool against a project looks like:

```text
$ detect_unused

⏳ Loading & Analyzing: [████████████████████████████] 100% | Completed!

==============================================================================
🔎 DEAD CODE & COMPREHENSIVE CODE AUDITOR REPORT
📁 Target Scope: [.]
📄 Dart Files:   59 scanned (out of 763 total in project)
==============================================================================

🚫 【1. Fully Commented-Out Files (100% Comments)】 - (2 files):
   🔴 [100% comments | 191 lines]: lib/presentation/pages/header.dart
      ↳ Commented classes found inside: [ Header ]
   🔴 [100% comments | 214 lines]: lib/presentation/widgets/multiselect.dart
      ↳ Commented classes found inside: [ DropDownMultiSelect ]

📦 【3. Active Files with Large Commented Code Blocks (>= 15 lines)】 - (2 files):
   🟡 lib/main.dart
      ↳ Lines [L400 - L414] (15 lines, 3 lines containing Dart syntax)
   🟡 lib/controllers/cart_controller.dart
      ↳ Lines [L152 - L178] (27 lines, 6 lines containing Dart syntax)

------------------------------------------------------------------------------

💀 【4. Unused & Dead Classes (Zero Project-wide References)】 - (3 classes):
   🔹 Category [Widget/Page] (2):
      ❌ [Public] DateInputField                   📍 lib/components/date_input.dart:262
      ❌ [Public] LastOrdersView                   📍 lib/views/last_orders_view.dart:3
   🔹 Category [Class] (1):
      ❌ [Public] LegacyPaymentHelper              📍 lib/utils/payment_helper.dart:48

🏠 【5. File-Internal Only Public Classes】 - (1 classes):
   🔸 _InternalFormatter                (Internal references: 4) 📍 lib/utils/formatter.dart:22

------------------------------------------------------------------------------

📋 【6. TODO Comments & Pending Tasks】 - (2 items):
   📝 [L14  ] lib/main.dart:14 ➜ implement initState
   📝 [L89  ] lib/services/api.dart:89 ➜ add retry timeout logic

------------------------------------------------------------------------------

🔍 【7. Dart Analyzer Diagnostics (Unused & Dead Elements)】 - (3 items):
   📦 [Unused & Unnecessary Imports] (1):
      ❌ lib/views/home.dart:3:8 ➜ Unused import: 'package:http/http.dart'.
   🏷️ [Unused Local Variables & Fields] (1):
      ❌ lib/controllers/user_controller.dart:42:9 ➜ The value of the local variable 'tempToken' isn't used.
   💀 [Dead Code & Null-Aware Expressions] (1):
      ❌ lib/utils/formatters.dart:30:12 ➜ Dead code.

==============================================================================
📊 FINAL AUDIT SUMMARY:
   - Fully commented-out files:          2
   - Heavily commented files:            0
   - Files with dead code blocks:        2
   - Dead classes (Zero usages):         3
   - File-internal only classes:         1
   - TODO pending tasks:                 2
   - Unused imports:                     1
   - Unused variables & fields:          1
   - Unused elements:                    0
   - Dead code & null-aware expr:        1
==============================================================================
```

---

## Installation

### As a Global CLI Tool
```bash
dart pub global activate detect_unused_code
```

### As a Dev Dependency (in `pubspec.yaml`)
```yaml
dev_dependencies:
  detect_unused_code: ^1.3.0
```

---

## CLI Usage

You can run the tool using the convenient short command **`detect_unused`** or the full package name **`detect_unused_code`**.

### Default All-in-One Run (All 13 Checks)
```bash
# Using the short command (recommended):
detect_unused

# Or using the full command name:
detect_unused_code

# Or via dart run inside your project:
dart run detect_unused_code
```

### Target Specific Folder or File
```bash
# Scan a specific directory
detect_unused --path=lib/features/checkout

# Scan a single file
detect_unused lib/services/payment_service.dart
```

### Filtering & Tuning Flags
```bash
# Audit only TODO comments
detect_unused --todos-only

# Audit only Dart analyzer diagnostics (unused imports, variables, dead code)
detect_unused --diagnostics-only

# Audit only unused/dead classes
detect_unused --unused-classes

# Audit only commented-out files and code blocks
detect_unused --commented

# Disable TODO inspection in full audit
detect_unused --no-todos

# Disable Dart analyzer diagnostics in full audit
detect_unused --no-diagnostics

# Custom comment threshold (e.g. flag files with 75%+ comments)
detect_unused --threshold 75

# Set minimum lines for commented code blocks
detect_unused --min-lines 20

# Export full analysis to a JSON file (creates detect_unused_code.json in current directory)
detect_unused --json

# Or specify a custom output JSON file name
detect_unused --json=audit_report.json

# Show code snippets for detected dead blocks
detect_unused -v
```

---

## CLI Options Reference

| Flag | Short | Default | Description |
| :--- | :--- | :--- | :--- |
| `--path=<dir>` / `--url=<dir>` | - | `.` | Target directory or file to audit |
| `--todos-only` | - | `false` | Audit only TODO tasks and pending notes |
| `--diagnostics-only` | `--analyzer-only` | `false` | Audit only Dart analyzer diagnostics |
| `--unused-classes` | `--classes` | `false` | Audit only unused/dead classes |
| `--commented` | `--comments` | `false` | Audit only commented-out files and blocks |
| `--no-todos` | - | `false` | Exclude TODO tasks from full audit |
| `--no-diagnostics` | - | `false` | Exclude Dart analyzer diagnostics from full audit |
| `--no-internal` | - | `false` | Exclude file-internal only public classes |
| `--threshold <int>` | - | `60` | Percentage threshold for heavily commented files |
| `--min-lines <int>` | - | `15` | Minimum lines to flag a dead block |
| `--json [filename]` | - | `false` | Save analysis report to a `.json` file (default: `detect_unused_code.json`) |
| `--verbose` | `-v` | `false` | Print samples of detected commented blocks |
| `--help` | `-h` | - | Display help message and exit |

---

## Programmatic API

You can call the auditor directly inside your Dart code or custom CI runner scripts:

```dart
import 'package:detect_unused_code/detect_unused_code.dart';

void main() {
  final auditor = UnusedCodeAuditor(
    options: const AuditorOptions(
      targetPath: 'lib',
      includeInternal: true,
      commentThreshold: 70,
      minBlockLines: 15,
    ),
  );

  final report = auditor.run(
    onProgress: (percent, stage) {
      print('$percent% - $stage');
    },
  );

  print('Dead classes: ${report.deadClasses.length}');
  for (final item in report.deadClasses) {
    print('- [${item.category}] ${item.name} (${item.relPath}:${item.line})');
  }

  print('TODO items: ${report.todos.length}');
  for (final item in report.todos) {
    print('- ${item.file}:${item.line} -> ${item.message}');
  }

  print('Unused imports: ${report.unusedImports.length}');
  print('Unused variables: ${report.unusedVariablesAndFields.length}');
}
```

---

## CI / CD Integration (GitHub Actions)

Add a step in your workflow to fail the build if dead code is detected:

```yaml
- name: Audit Dead Code
  run: dart run detect_unused_code
```

The CLI returns exit code `1` when dead classes, fully commented files, or unused analyzer diagnostics are found, and `0` when the code is clean.

---

## دليل الاستخدام السريع وأهمية المكتبة (باللغة العربية)

### لماذا يحتاج كل مشروع Flutter و Dart لهذه المكتبة؟
محلل دارت الافتراضي (`flutter analyze`) **لا يكتشف أبداً الكلاسات والـ Widgets العامة غير المستخدمة**، لأن طبيعة Dart تعتبر أي كلاس `public` قابلاً للاستيراد الخارجي.

في المشاريع المتوسطة والكبيرة، تتراكم الديون التقنية:
- **كلاسات و Widgets مهجورة**: شاشات، Widgets، و Dialogs لم تعد مستخدمة في أي مكان.
- **ملفات معطلة بالكامل (100% Comments)**: ملفات تم تعليق محتواها بـ `/* ... */` وظلت تزيد من حجم المشروع.
- **بلوكات برمجية معلقة**: كتل كود تزيد عن 15 سطر معلقة داخل ملفات حية.
- **مهام معلقة (TODOs)**: استخراج جميع الـ TODOs بدقة مع أرقام الأسطر والوصف.
- **تشخيصات الرموز المهملة**: اكتشاف الاستيرادات الزائدة، المتغيرات غير المستخدمة، الأكواد غير القابلة للوصول، والتعبيرات الميتة.

تقوم المكتبة بفحص شامل لكل هذه النقاط الـ 13 دفعة واحدة بدون أي حزم خارجية (Zero Dependencies).

### أوامر سريعة (باستخدام الأمر المختصر `detect_unused`):
- **فحص شامل لكافة النقاط الـ 13:**
  ```bash
  detect_unused
  # أو عبر dart run:
  dart run detect_unused_code
  ```
- **فحص مجلد معين (مثل lib):**
  ```bash
  detect_unused --path="lib"
  ```
- **فحص الـ TODOs فقط:**
  ```bash
  detect_unused --todos-only
  ```
- **فحص تشخيصات المحلل فقط (unused imports, variables, dead code):**
  ```bash
  detect_unused --diagnostics-only
  ```
- **استخراج الكلاسات والـ Widgets المهجورة فقط:**
  ```bash
  detect_unused --unused-classes
  ```
- **تصدير التقرير كاملاً إلى ملف JSON (ينشئ ملف detect_unused_code.json في نفس المجلد):**
  ```bash
  detect_unused --json
  # أو تحديد اسم مخصص للملف:
  detect_unused --json=report.json
  ```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
