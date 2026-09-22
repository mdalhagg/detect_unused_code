import 'dart:io';

import 'package:detect_unused_code/detect_unused_code.dart';

void main(List<String> args) {
  final runner = CliRunner(args);
  final exitCode = runner.run();
  exit(exitCode);
}
