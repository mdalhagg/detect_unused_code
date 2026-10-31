import 'dart:io';

/// Set of directory names to ignore during Dart file discovery.
const ignoredDirNames = {
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
  '.windsurf',
  'Flashpost-tests',
  '.detect_unused',
  'detect_unused',
  'backups',
  '.backups',
  'backup',
  '.backup',
};

/// Keywords used to detect whether a commented line contains Dart code syntax.
const dartSyntaxKeywords = [
  'import ',
  'export ',
  'class ',
  'abstract class ',
  'extends ',
  'implements ',
  'with ',
  'Widget ',
  'State<',
  'StatefulWidget',
  'StatelessWidget',
  'BuildContext',
  'setState(',
  'initState()',
  'dispose()',
  'build(',
  'return ',
  '@override',
  'final ',
  'const ',
  'late ',
  'void ',
  'Future<',
  'Stream<',
  'Controller',
  'Provider',
  'Text(',
  'Container(',
  'Scaffold(',
  'Column(',
  'Row(',
];

/// Normalizes and trims path strings from quotes, extra slashes, and leading `./`.
String cleanInputPath(String s) {
  var p = s.trim();
  while (p.startsWith('"') ||
      p.startsWith("'") ||
      p.endsWith('"') ||
      p.endsWith("'")) {
    p = p.replaceAll(RegExp(r'''^["']+|["']+$'''), '');
  }
  p = p.replaceAll(r'\', '/');
  p = p.replaceAll(RegExp(r'/+'), '/');
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  while (p.endsWith('/') && p.length > 1) {
    p = p.substring(0, p.length - 1);
  }
  return p.trim();
}

/// Converts a path to an absolute, normalized, lower-case canonical path.
String canonicalizePath(String p) {
  var norm = p.replaceAll(r'\', '/').replaceAll(RegExp(r'/+'), '/');
  if (!norm.startsWith('/') && !RegExp(r'^[a-zA-Z]:').hasMatch(norm)) {
    final cur = Directory.current.path.replaceAll(r'\', '/');
    norm = '$cur/$norm';
  }

  final segments = norm.split('/');
  final resolved = <String>[];
  for (final seg in segments) {
    if (seg == '..') {
      if (resolved.isNotEmpty) {
        resolved.removeLast();
      }
    } else if (seg != '.' && seg.isNotEmpty) {
      resolved.add(seg);
    }
  }

  var result = resolved.join('/');
  if (RegExp(r'^[a-zA-Z]:$').hasMatch(result)) {
    result = '$result/';
  }
  return result.toLowerCase();
}

/// Converts a system path to a clickable `file://` URI string, optionally with line and column.
String toFileUri(String p, {int? line, int? column}) {
  var norm = p.replaceAll(r'\', '/').replaceAll(RegExp(r'/+'), '/');
  if (!norm.startsWith('/') && !RegExp(r'^[a-zA-Z]:').hasMatch(norm)) {
    final cur = Directory.current.path.replaceAll(r'\', '/');
    norm = '$cur/$norm';
  }

  final segments = norm.split('/');
  final resolved = <String>[];
  for (final seg in segments) {
    if (seg == '..') {
      if (resolved.isNotEmpty) {
        resolved.removeLast();
      }
    } else if (seg != '.' && seg.isNotEmpty) {
      resolved.add(seg);
    }
  }

  var cleanPath = resolved.join('/');
  if (!cleanPath.startsWith('/')) {
    cleanPath = '/$cleanPath';
  }

  var uri = 'file://$cleanPath';
  if (line != null) {
    uri = '$uri:$line';
    if (column != null) {
      uri = '$uri:$column';
    }
  }
  return uri;
}

/// Returns the relative path from [basePath] to [fullPath].
String getRelativePath(String fullPath, String basePath) {
  final normFull =
      fullPath.replaceAll(r'\', '/').replaceAll(RegExp(r'/+'), '/');
  final canonFull = canonicalizePath(fullPath);
  final canonBase = canonicalizePath(basePath);
  if (canonFull.startsWith(canonBase)) {
    var rel = normFull.substring(canonBase.length);
    if (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    return rel;
  }

  // Handle Windows 8.3 short paths (e.g. DEV74~1.THA vs dev74.THARWAT)
  try {
    final realFull = File(fullPath).existsSync()
        ? File(fullPath).resolveSymbolicLinksSync()
        : fullPath;
    final realBase = Directory(basePath).existsSync()
        ? Directory(basePath).resolveSymbolicLinksSync()
        : basePath;
    final canonRealFull = canonicalizePath(realFull);
    final canonRealBase = canonicalizePath(realBase);
    if (canonRealFull.startsWith(canonRealBase)) {
      final normRealFull = realFull.replaceAll(r'\', '/');
      var rel = normRealFull.substring(canonRealBase.length);
      if (rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      return rel;
    }
  } catch (_) {}

  // Guarantee that the result never contains an absolute drive prefix like 'C:'
  var safe = normFull.replaceFirst(RegExp(r'^[a-zA-Z]:[/\\].*?'), '');
  if (normFull.startsWith(RegExp(r'^[a-zA-Z]:'))) {
    safe = normFull.substring(2);
  }
  if (safe.startsWith('/')) {
    safe = safe.substring(1);
  }
  return safe;
}

/// Automatically searches for and resolves the project root directory.
Directory findProjectOrWorkspaceRoot([Directory? startDir]) {
  final dir = startDir ?? Directory.current;

  // 1. Check if current directory contains pubspec.yaml
  if (File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path != dir.path) {
      if (File('${parent.path}/melos.yaml').existsSync()) {
        return parent;
      }
    }
    return dir;
  }

  // 2. Search upward for pubspec.yaml or monorepo markers
  var probe = dir;
  while (probe.path != probe.parent.path) {
    if (File('${probe.path}/pubspec.yaml').existsSync() ||
        File('${probe.path}/melos.yaml').existsSync()) {
      return probe;
    }
    probe = probe.parent;
  }

  return dir;
}

/// Resolves user input into a target directory or file entity within [projectRoot].
FileSystemEntity resolveTargetPath(
  String? input,
  Directory projectRoot, {
  bool isJson = false,
}) {
  if (input == null || input.trim().isEmpty) {
    return projectRoot;
  }

  final cleaned = cleanInputPath(input);

  // Check direct path first (especially when absolute)
  try {
    final directDir = Directory(cleaned);
    if (directDir.existsSync()) {
      return directDir;
    }
  } catch (_) {}

  try {
    final directFile = File(cleaned);
    if (directFile.existsSync()) {
      return directFile;
    }
  } catch (_) {}

  final candidates = [
    Directory('${projectRoot.path}/$cleaned'),
    File('${projectRoot.path}/$cleaned'),
    Directory('${Directory.current.path}/$cleaned'),
    File('${Directory.current.path}/$cleaned'),
  ];

  for (final c in candidates) {
    try {
      if (c.existsSync()) {
        return c;
      }
    } catch (_) {}
  }

  if (!isJson) {
    print(
        '⚠️ Note: Specified target path "$input" was not found, falling back to project root.');
  }
  return projectRoot;
}

/// Recursively scans and collects all `.dart` files under [entity].
List<File> walkDartFiles(FileSystemEntity entity) {
  final results = <File>[];
  if (!entity.existsSync()) {
    return results;
  }

  final normEntityPath = entity.path.replaceAll(r'\', '/').toLowerCase();
  if (normEntityPath.contains('/.detect_unused') ||
      normEntityPath.contains('/backups') ||
      normEntityPath.contains('/.backups') ||
      normEntityPath.endsWith('/backup') ||
      normEntityPath.contains('/backup/')) {
    return results;
  }

  if (entity is File) {
    if (entity.path.endsWith('.dart')) {
      results.add(entity);
    }
    return results;
  }

  if (entity is Directory) {
    try {
      final entries = entity.listSync(followLinks: false);
      for (final entry in entries) {
        final normPath = entry.path.replaceAll(r'\', '/').toLowerCase();
        if (normPath.contains('/.detect_unused') ||
            normPath.contains('/backups') ||
            normPath.contains('/.backups') ||
            normPath.endsWith('/backup') ||
            normPath.contains('/backup/')) {
          continue;
        }

        final name = entry.uri.pathSegments.isNotEmpty
            ? entry.uri.pathSegments[
                entry.uri.pathSegments.length - (entry is Directory ? 2 : 1)]
            : '';
        if (ignoredDirNames.contains(name)) {
          continue;
        }

        if (entry is Directory) {
          results.addAll(walkDartFiles(entry));
        } else if (entry is File && entry.path.endsWith('.dart')) {
          results.add(entry);
        }
      }
    } catch (_) {}
  }
  return results;
}

/// Checks whether a single line of text matches known Dart syntax keywords.
bool isDartCodeLine(String text) {
  return dartSyntaxKeywords.any((kw) => text.contains(kw));
}

/// Extracts declared class, enum, and mixin names that are commented out in [content].
List<String> extractCommentedClasses(String content) {
  final regex = RegExp(
    r'(?://|/\*|\*)\s*(?:(?:abstract\s+|base\s+|sealed\s+)?class|enum|mixin)\s+([A-Za-z0-9_$]+)',
  );
  final found = <String>{};
  for (final match in regex.allMatches(content)) {
    final name = match.group(1);
    if (name != null && name.length > 1) {
      found.add(name);
    }
  }
  return found.toList();
}

/// Strips all block comments, single-line comments, and string literals from [content]
/// while preserving exact line offsets and character positions.
String stripCommentsAndStrings(String content) {
  final buffer = StringBuffer();
  int idx = 0;
  final len = content.length;

  while (idx < len) {
    final c = content[idx];

    // Check for comments
    if (c == '/' && idx + 1 < len) {
      final next = content[idx + 1];

      // Single-line comment: //
      if (next == '/') {
        idx += 2;
        while (idx < len && content[idx] != '\n' && content[idx] != '\r') {
          buffer.write(' ');
          idx++;
        }
        continue;
      }

      // Multi-line block comment: /* ... */
      if (next == '*') {
        buffer.write('  ');
        idx += 2;
        int depth = 1;
        while (idx < len && depth > 0) {
          if (content[idx] == '/' && idx + 1 < len && content[idx + 1] == '*') {
            depth++;
            buffer.write('  ');
            idx += 2;
            continue;
          }
          if (content[idx] == '*' && idx + 1 < len && content[idx + 1] == '/') {
            depth--;
            buffer.write('  ');
            idx += 2;
            continue;
          }
          if (content[idx] == '\n') {
            buffer.write('\n');
          } else if (content[idx] == '\r') {
            buffer.write('\r');
          } else {
            buffer.write(' ');
          }
          idx++;
        }
        continue;
      }
    }

    // Check for raw strings: r'...' or r"..."
    bool isRaw = false;
    if ((c == 'r' || c == 'R') &&
        idx + 1 < len &&
        (content[idx + 1] == "'" || content[idx + 1] == '"')) {
      isRaw = true;
      buffer.write(' ');
      idx++;
    }

    // Check for string literals: ''' or """ or ' or "
    if (idx < len && (content[idx] == "'" || content[idx] == '"')) {
      final quote = content[idx];
      final isTriple = idx + 2 < len &&
          content[idx + 1] == quote &&
          content[idx + 2] == quote;

      if (isTriple) {
        buffer.write('   ');
        idx += 3;
        while (idx < len) {
          if (content[idx] == quote &&
              idx + 2 < len &&
              content[idx + 1] == quote &&
              content[idx + 2] == quote) {
            buffer.write('   ');
            idx += 3;
            break;
          }
          if (!isRaw && content[idx] == '\\' && idx + 1 < len) {
            if (content[idx + 1] == '\n') {
              buffer.write(' \n');
            } else {
              buffer.write('  ');
            }
            idx += 2;
            continue;
          }
          if (content[idx] == '\n') {
            buffer.write('\n');
          } else if (content[idx] == '\r') {
            buffer.write('\r');
          } else {
            buffer.write(' ');
          }
          idx++;
        }
        continue;
      } else {
        // Single-line string
        buffer.write(' ');
        idx++;
        while (idx < len) {
          final cur = content[idx];
          if (cur == quote) {
            buffer.write(' ');
            idx++;
            break;
          }
          if (cur == '\n' || cur == '\r') {
            // Unclosed string on newline
            break;
          }
          if (!isRaw && cur == '\\' && idx + 1 < len) {
            buffer.write('  ');
            idx += 2;
            continue;
          }
          buffer.write(' ');
          idx++;
        }
        continue;
      }
    }

    // Regular code character
    buffer.write(c);
    idx++;
  }

  return buffer.toString();
}

/// Counts how many times [className] is referenced within its declaring file,
/// excluding the declaration header itself.
int countInternalUsages(String cleanCode, String className) {
  final declRegex = RegExp(
    r'\b(?:(?:abstract\s+|base\s+|sealed\s+|interface\s+|final\s+)?class|(?:enum)|(?:mixin)|(?:extension\s+type)|(?:extension))\s+' +
        RegExp.escape(className) +
        r'\b',
  );
  final match = declRegex.firstMatch(cleanCode);
  if (match == null) {
    return 0;
  }

  final startIdx = match.start;
  final nextSemicolon = cleanCode.indexOf(';', startIdx);
  final openBrace = cleanCode.indexOf('{', startIdx);

  if (openBrace == -1 || (nextSemicolon != -1 && nextSemicolon < openBrace)) {
    final endIdx = nextSemicolon != -1 ? nextSemicolon + 1 : match.end;
    final before = cleanCode.substring(0, startIdx);
    final after = endIdx < cleanCode.length ? cleanCode.substring(endIdx) : '';
    final wordRegex = RegExp(r'\b' + RegExp.escape(className) + r'\b');
    return wordRegex.allMatches(before).length +
        wordRegex.allMatches(after).length;
  }

  int depth = 1;
  int idx = openBrace + 1;
  while (idx < cleanCode.length && depth > 0) {
    final char = cleanCode[idx];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
    }
    idx++;
  }

  final before = cleanCode.substring(0, startIdx);
  final after = idx < cleanCode.length ? cleanCode.substring(idx) : '';
  final wordRegex = RegExp(r'\b' + RegExp.escape(className) + r'\b');
  return wordRegex.allMatches(before).length +
      wordRegex.allMatches(after).length;
}

/// Safe collection extensions compatible with Dart >= 2.17.0.
extension SafeIterableExtension<T> on Iterable<T> {
  /// Returns the last element, or `null` if the iterable is empty.
  T? get safeLast => isEmpty ? null : last;

  /// Returns the first element, or `null` if the iterable is empty.
  T? get safeFirst => isEmpty ? null : first;
}

/// Suffixes identifying auto-generated Dart source files.
const generatedFileSuffixes = [
  '.g.dart',
  '.freezed.dart',
  '.mapper.dart',
  '.mocks.dart',
  '.config.dart',
  '.gr.dart',
  '.gen.dart',
  '.drift.dart',
  '.reflectable.dart',
  '.gql.dart',
  '.route.dart',
  '.chopper.dart',
  '.swagger.dart',
  '.auto_mappr.dart',
];

/// Checks whether the given file path represents a generated Dart file.
bool isGeneratedDartFile(String path) {
  final lower = path.toLowerCase().replaceAll(r'\', '/');
  for (final suffix in generatedFileSuffixes) {
    if (lower.endsWith(suffix)) {
      return true;
    }
  }
  if (lower.contains('/generated/') || lower.startsWith('generated/')) {
    return true;
  }
  return false;
}

/// Checks if a file path matches any custom exclude pattern or substring.
///
/// Supports exact substrings, directory paths (e.g. `test/mocks/`),
/// simple wildcards (e.g. `*.g.dart`), and glob expressions (e.g. `**/generated/**`, `lib/*/test.dart`).
bool matchesCustomExclude(String path, List<String> excludes) {
  if (excludes.isEmpty) return false;
  final norm = path.replaceAll(r'\', '/').toLowerCase();
  for (final raw in excludes) {
    var pat = raw.trim().replaceAll(r'\', '/').toLowerCase();
    if ((pat.startsWith('"') && pat.endsWith('"')) ||
        (pat.startsWith("'") && pat.endsWith("'"))) {
      if (pat.length >= 2) {
        pat = pat.substring(1, pat.length - 1).trim();
      }
    }
    if (pat.isEmpty) continue;

    if (pat.contains('*')) {
      var regex = RegExp.escape(pat);
      regex = regex.replaceAll(r'\*\*/', r'(?:^|.*?/)');
      regex = regex.replaceAll(r'/\*\*', r'(?:/.*)?');
      regex = regex.replaceAll(r'\*\*', r'.*');
      regex = regex.replaceAll(r'\*', r'[^/]*');

      if (!regex.startsWith('(?:^|.*?/)') &&
          !regex.startsWith('^') &&
          !regex.startsWith('/')) {
        regex = '(?:^|/)$regex';
      }
      if (!regex.endsWith(r'$')) {
        regex = '$regex\$';
      }

      try {
        final reg = RegExp(regex, caseSensitive: false);
        if (reg.hasMatch(norm)) return true;
      } catch (_) {
        if (norm.contains(pat.replaceAll('*', ''))) return true;
      }
    } else {
      if (norm.contains(pat)) return true;
    }
  }
  return false;
}

/// Reads custom exclusion patterns from the project's `pubspec.yaml` file under
/// `detect_unused_code:` or `detect_unused:` (keys `exclude:` or `ignore:`).
List<String> loadPubspecExcludes(Directory projectRoot) {
  final pubspecFile = File('${projectRoot.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    return const [];
  }

  try {
    final lines = pubspecFile.readAsLinesSync();
    bool inDetectSection = false;
    bool inExcludeSection = false;
    int detectIndent = 0;
    int excludeIndent = 0;
    final excludes = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final trimmed = rawLine.trim();

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final indent = rawLine.indexOf(rawLine.trimLeft());

      if (inDetectSection) {
        if (indent <= detectIndent && !trimmed.startsWith('-')) {
          inDetectSection = false;
          inExcludeSection = false;
        }
      }

      if (!inDetectSection) {
        if (trimmed == 'detect_unused_code:' ||
            trimmed == 'detect_unused:' ||
            trimmed.startsWith('detect_unused_code:') ||
            trimmed.startsWith('detect_unused:')) {
          inDetectSection = true;
          detectIndent = indent;
          inExcludeSection = false;
        }
        continue;
      }

      // Inside detect_unused_code section
      if (inExcludeSection) {
        if (indent <= excludeIndent && !trimmed.startsWith('-')) {
          inExcludeSection = false;
        } else if (trimmed.startsWith('-')) {
          var item = trimmed.substring(1).trim();
          if (item.contains('#') &&
              !item.startsWith('"') &&
              !item.startsWith("'")) {
            item = item.substring(0, item.indexOf('#')).trim();
          } else if ((item.startsWith('"') && item.contains('"')) ||
              (item.startsWith("'") && item.contains("'"))) {
            final quote = item[0];
            final close = item.indexOf(quote, 1);
            if (close != -1) {
              item = item.substring(1, close).trim();
            }
          }
          if (item.isNotEmpty && !excludes.contains(item)) {
            excludes.add(item);
          }
          continue;
        }
      }

      if (trimmed == 'exclude:' ||
          trimmed == 'ignore:' ||
          trimmed.startsWith('exclude:') ||
          trimmed.startsWith('ignore:')) {
        inExcludeSection = true;
        excludeIndent = indent;
        continue;
      }
    }

    return excludes;
  } catch (_) {
    return const [];
  }
}

/// Checks whether the file header contains a file-level directive to ignore unused code.
bool hasFileKeepUnusedDirective(String fileContent) {
  final lines = fileContent.split('\n');
  final limit = lines.length < 35 ? lines.length : 35;
  for (int i = 0; i < limit; i++) {
    final line = lines[i].trim().toLowerCase();
    if (line.contains('ignore_for_file:') && line.contains('unused_code')) {
      return true;
    }
    if (line.contains('@keepunusedfile') ||
        line.contains('@keep-unused-file') ||
        line == '// @keepunused' ||
        line == '/// @keepunused') {
      return true;
    }
  }
  return false;
}

/// Directives that indicate a class or element should be preserved and not marked as unused.
const keepUnusedDirectives = [
  '@keepunused',
  '@keep-unused',
  '// @keepunused',
  '/// @keepunused',
  '// @keep-unused',
  '/// @keep-unused',
  '// keep-unused',
  '/// keep-unused',
  '// ignore: unused_code',
  '/// ignore: unused_code',
];

/// Checks if preceding lines before [classLineIndex] contain a keep-unused directive or annotation.
bool hasKeepUnusedDirective(List<String> rawLines, int classLineIndex) {
  int lookback = 0;
  for (int i = classLineIndex - 1; i >= 0 && lookback < 6; i--) {
    final line = rawLines[i].trim();
    if (line.isEmpty) {
      lookback++;
      continue;
    }
    if (line.startsWith('class ') ||
        line.startsWith('abstract ') ||
        line.startsWith('enum ') ||
        line.startsWith('mixin ') ||
        line == '}') {
      break;
    }
    final lower = line.toLowerCase();
    for (final dir in keepUnusedDirectives) {
      if (lower.contains(dir)) {
        return true;
      }
    }
    lookback++;
  }
  return false;
}

/// Annotations typically associated with Dependency Injection, Service Locators,
/// or modular registration that construct or register instances indirectly.
const diAnnotations = [
  '@injectable',
  '@singleton',
  '@lazysingleton',
  '@named',
  '@module',
  '@factorymethod',
  '@riverpod',
  '@entrypoint',
  '@pragma',
];

/// Checks if preceding lines before [classLineIndex] contain a Dependency Injection annotation.
bool hasDependencyInjectionAnnotation(
    List<String> rawLines, int classLineIndex) {
  int lookback = 0;
  for (int i = classLineIndex - 1; i >= 0 && lookback < 6; i--) {
    final line = rawLines[i].trim();
    if (line.isEmpty) {
      lookback++;
      continue;
    }
    if (line.startsWith('class ') ||
        line.startsWith('abstract ') ||
        line.startsWith('enum ') ||
        line.startsWith('mixin ') ||
        line == '}') {
      break;
    }
    final lower = line.toLowerCase();
    for (final ann in diAnnotations) {
      if (lower.startsWith(ann) ||
          lower.contains('$ann(') ||
          lower.contains('$ann ')) {
        return true;
      }
    }
    lookback++;
  }
  return false;
}
