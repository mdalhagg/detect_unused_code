import 'package:detect_unused_code/detect_unused_code.dart';

void main() {
  // 1. Initialize auditor for the current project or a specific directory
  final auditor = UnusedCodeAuditor(
    options: const AuditorOptions(
      // targetPath: 'lib/features', // optional: limit scan scope
      includeInternal: true,
      commentThreshold: 60,
      minBlockLines: 15,
    ),
  );

  // 2. Run analysis with progress monitoring
  final report = auditor.run(
    onProgress: (percent, message) {
      print('[$percent%] $message');
    },
  );

  // 3. Inspect results
  print('\n--- Audit Summary ---');
  print('Target: ${report.targetPath}');
  print('Scanned files: ${report.totalTargetDartFiles}');
  print('Dead classes: ${report.deadClasses.length}');
  print('Internal-only classes: ${report.internalOnlyClasses.length}');
  print('Fully commented files: ${report.fullyCommentedFiles.length}');
  print('Files with dead blocks: ${report.filesWithCommentBlocks.length}');

  for (final deadClass in report.deadClasses) {
    print(
        'Dead class: ${deadClass.name} at ${deadClass.relPath}:${deadClass.line}');
  }
}
