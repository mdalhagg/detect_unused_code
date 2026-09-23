# detect_unused_code

[![pub package](https://img.shields.io/pub/v/detect_unused_code.svg)](https://pub.dev/packages/detect_unused_code)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D2.17.0%20%3C4.0.0-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

A static analysis tool and Dart library to detect dead classes, unused widgets, commented-out files, and abandoned code blocks across Dart and Flutter projects.

Works with zero external dependencies, runs on any Dart SDK from `2.17.0` up to Dart `3.x` / `4.x`, and supports both CLI usage and programmatic Dart API.

---

## Why Is This Critical for Medium & Large Projects?

Standard `dart analyze` / `flutter analyze` is great for syntax and unused private fields (`_myVar`), but **it cannot detect unused public classes, widgets, or models**. In Dart, public classes are considered potential library exports, so the compiler will never warn you if a public `Widget`, `Controller`, or `Model` is completely abandoned.

In growing codebases (50+ to 1,000+ files), technical debt accumulates fast:
- **Forgotten Widgets & Screens**: Refactored pages leave behind dialogs, input fields, and widgets that nothing references anymore.
- **100% Commented-Out Files**: Old implementations commented out with `/* ... */` during a quick fix and forgotten forever.
- **Dead Code Blocks**: Large chunks of abandoned logic (20+ lines) remaining inside active production files.
- **Orphaned Public Classes**: Helper classes used in only one file that should either be private (`_`) or deleted.

This tool solves that gap by scanning your entire workspace, cross-referencing declarations against active code, and reporting exact file paths and line numbers in seconds.

---

## Example Audit Output

Here is what running the tool against an active production project looks like:

```text
$ detect_unused_code --path="lib"

⏳ Loading & Analyzing: [████████████████████████████] 100% | Completed!

==============================================================================
🔎 DEAD CODE & UNUSED CLASSES AUDITOR REPORT
📁 Target Scope: [lib]
📄 Dart Files:   59 scanned (out of 763 total in project)
==============================================================================

🚫 【1. Fully Commented-Out Files (100% Comments)】 - (2 files):
   (These files contain entirely commented-out code and can be safely deleted or restored)
   🔴 [100% comments | 191 lines]: lib/presentation/pages/dashbord_module/components/header.dart
      ↳ Commented classes found inside: [ Header ]
   🔴 [100% comments | 214 lines]: lib/presentation/widgets/multiselect.dart
      ↳ Commented classes found inside: [ _TheState, _SelectRow, DropDownMultiSelect, _DropDownMultiSelectState ]

📦 【3. Active Files with Large Commented Code Blocks (>= 15 lines)】 - (5 files):
   🟡 lib/main.dart
      ↳ Lines [L400 - L414] (15 lines, 3 lines containing Dart syntax)
   🟡 lib/presentation/pages/dashbord_module/dashbord_controller.dart
      ↳ Lines [L152 - L178] (27 lines, 6 lines containing Dart syntax)
   🟡 lib/presentation/pages/dashbord_module/pages/more.dart
      ↳ Lines [L291 - L323] (33 lines, 7 lines containing Dart syntax)
   🟡 lib/singelton/global_service.dart
      ↳ Lines [L1330 - L1355] (26 lines, 6 lines containing Dart syntax)
   🟡 lib/utils/helper.dart
      ↳ Lines [L8 - L27] (20 lines, 3 lines containing Dart syntax)

------------------------------------------------------------------------------

💀 【4. Unused & Dead Classes (Zero Project-wide References)】 - (7 classes):
   (Classes declared in this scope that have 0 external references across the entire workspace)

   🔹 Category [Widget/Page] (4):
      ❌ [Public] DateInputField                   📍 lib/presentation/pages/dashbord_module/components/all_last_orders_widget.dart:262
      ❌ [Public] MerchantDateInputField           📍 lib/presentation/pages/dashbord_module/components/all_last_orders_widget.dart:300
      ❌ [Public] LastOrdersView                   📍 lib/presentation/pages/dashbord_module/components/last_orders_view.dart:3
      ❌ [Public] Wallet                           📍 lib/presentation/pages/dashbord_module/components/wallet.dart:4

   🔹 Category [Class] (3):
      ❌ [Public] ServiceItem                      📍 lib/services/entities/services.dart:3
      ❌ [Public] ClassYouImplemented              📍 lib/utils/helper.dart:48
      ❌ [Public] MyCustomScrollBehavior           📍 lib/utils/my_custom_scroll_behavior.dart:5

💡 Note: Found 16 public classes used internally only. To display them, re-run with --include-internal

==============================================================================
📊 FINAL AUDIT SUMMARY:
   - Fully commented-out files:          2
      ↳ lib/presentation/pages/dashbord_module/components/header.dart
      ↳ lib/presentation/widgets/multiselect.dart
   - Heavily commented files:            0
   - Files with dead code blocks:        5
      ↳ lib/main.dart
      ↳ lib/presentation/pages/dashbord_module/dashbord_controller.dart
      ↳ lib/presentation/pages/dashbord_module/pages/more.dart
      ↳ lib/singelton/global_service.dart
      ↳ lib/utils/helper.dart
   - Dead classes (Zero usages):         7
      ↳ lib/presentation/pages/dashbord_module/components/all_last_orders_widget.dart  :: [DateInputField, MerchantDateInputField]
      ↳ lib/presentation/pages/dashbord_module/components/last_orders_view.dart  :: [LastOrdersView]
      ↳ lib/presentation/pages/dashbord_module/components/wallet.dart  :: [Wallet]
      ↳ lib/services/entities/services.dart  :: [ServiceItem]
      ↳ lib/utils/helper.dart  :: [ClassYouImplemented]
      ↳ lib/utils/my_custom_scroll_behavior.dart  :: [MyCustomScrollBehavior]
   - File-internal only classes:         16
==============================================================================
```

---

## What It Finds

1. **Unused & Dead Classes**: Declared classes, widgets, mixins, enums, extensions, and controllers that have 0 references across the entire project.
2. **File-Internal Only Public Classes**: Public classes that are only used inside their declaring file (candidates to become private `_` or to be deleted).
3. **Fully Commented-Out Files**: Files where 90%+ of the content is commented-out code (extracts the commented class names).
4. **Heavily Commented Files**: Active files exceeding a configurable comment percentage threshold (default: 60%).
5. **Large Dead Code Blocks**: Abandoned multi-line code blocks commented out inside active files (default: 15+ consecutive lines).

---

## Installation

### As a Global CLI Tool
```bash
dart pub global activate detect_unused_code
```

### As a Dev Dependency (in `pubspec.yaml`)
```yaml
dev_dependencies:
  detect_unused_code: ^1.0.0
```

Or run via local path during development:
```yaml
dev_dependencies:
  detect_unused_code:
    path: ../path/to/detect_unused_code
```

---

## CLI Usage

You can run the tool using the convenient short command **`detect_unused`** or the full package name **`detect_unused_code`**.

### Quick Run
```bash
# Using the short command (recommended if activated globally):
detect_unused

# Or using the full command name:
detect_unused_code

# Or via dart run inside your project:
dart run detect_unused_code:detect_unused
# or simply:
dart run detect_unused_code
```

### Target Specific Folder or File
```bash
# Scan a specific directory
detect_unused --path=lib/features/checkout

# Scan a single file
detect_unused lib/services/payment_service.dart
```

### Common Flags
```bash
# Only find unused classes (skip comment checks)
detect_unused --unused-classes

# Include file-internal public classes
detect_unused --unused-classes --include-internal

# Only find commented-out files and code blocks
detect_unused --commented

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
| `--unused-classes` | `--classes` | `false` | Audit only unused classes |
| `--commented` | `--comments` | `false` | Audit only commented-out files and blocks |
| `--include-internal` | - | `false` | Report public classes with 0 external references |
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

  print('Fully commented files: ${report.fullyCommentedFiles.length}');
}
```

---

## CI / CD Integration (GitHub Actions)

Add a step in your workflow to fail the build if dead code is detected:

```yaml
- name: Audit Dead Code
  run: dart run detect_unused_code --unused-classes
```

The CLI returns exit code `1` when dead classes or 100% commented-out files are found, and `0` when the code is clean.

---

## How It Works

1. **Stripping Phase**: Removes multi-line strings, single-line strings, and comments without disturbing line offsets. This avoids false positives from comments mentioning class names or string literals.
2. **Declaration Extraction**: Uses regex to identify declarations of `class`, `abstract class`, `enum`, `mixin`, `extension`, and classifies them by architectural role (`Widget/Page`, `Controller`, `Entity/Model`, `Service/Repository`).
3. **Usage Cross-Checking**: Searches for whole-word occurrences of each declared identifier across all non-comment project code.
4. **Internal vs External Scope**: Distinguishes between usages in other files versus local usage within the declaring file.

---

## دليل الاستخدام السريع وأهمية المكتبة (باللغة العربية)

### لماذا يحتاج كل مشروع Flutter و Dart كبير لهذه المكتبة؟
محلل دارت الافتراضي (`flutter analyze`) **لا يكتشف أبداً الكلاسات والـ Widgets العامة غير المستخدمة**، لأن طبيعة Dart تعتبر أي كلاس `public` قابلاً للاستيراد الخارجي.

في المشاريع المتوسطة والكبيرة (من 50 إلى مئات الملفات)، تتراكم الأكواد الميتة:
- **شاشات وعناصر قديمة**: شاشات، Widgets، و Dialogs تم استبدالها بتصميم جديد وظلت معلقة في المشروع بدون أي استدعاء.
- **ملفات معطلة بالكامل (100% Comments)**: ملفات تم تعليق محتواها بـ `/* ... */` أثناء التجارب والـ Debugging وتُركت تزيد من حجم المشروع وتشتت الفريق.
- **بلوكات برمجية مهجورة**: كتل كود تزيد عن 15 سطر معلقة داخل ملفات حية.

هذه الأداة تقوم بفحص كامل المشروع في ثوانٍ معدودة وبدون أي حزم إضافية (Zero Dependencies)، وتعطيك تقريراً بالأرقام ومسارات الملفات وأرقام الأسطر لتنظيف مشروعك فوراً.

### أوامر سريعة (باستخدام الأمر المختصر `detect_unused`):
- **فحص كامل المشروع:**
  ```bash
  detect_unused
  # أو عبر dart run:
  dart run detect_unused_code
  ```
- **فحص مجلد معين (مثل lib):**
  ```bash
  detect_unused --path="lib"
  ```
- **استخراج الكلاسات والـ Widgets المهجورة فقط:**
  ```bash
  detect_unused --unused-classes
  ```
- **تضمين الكلاسات المستخدمة محلياً فقط داخل ملفها:**
  ```bash
  detect_unused --unused-classes --include-internal
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
