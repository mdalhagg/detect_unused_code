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
  return normFull;
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

  final candidates = [
    Directory('${Directory.current.path}/$cleaned'),
    File('${Directory.current.path}/$cleaned'),
    Directory('${projectRoot.path}/$cleaned'),
    File('${projectRoot.path}/$cleaned'),
    Directory(cleaned),
    File(cleaned),
  ];

  for (final c in candidates) {
    if (c.existsSync()) {
      return c;
    }
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
/// while preserving exact line offsets.
String stripCommentsAndStrings(String content) {
  // 1. Multi-line block comments /* ... */ (preserve line count)
  String clean = content.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/'),
    (m) => '\n' * (m.group(0)!.split('\n').length - 1),
  );

  // 2. Triple quoted multi-line strings ''' or """ (preserve line count)
  clean = clean.replaceAllMapped(
    RegExp(r"'''[\s\S]*?'''"),
    (m) => '\n' * (m.group(0)!.split('\n').length - 1),
  );
  clean = clean.replaceAllMapped(
    RegExp(r'"""[\s\S]*?"""'),
    (m) => '\n' * (m.group(0)!.split('\n').length - 1),
  );

  // 3. Single-line strings '...' and "..."
  clean = clean.replaceAll(RegExp(r"'(?:[^'\r\n\\]|\\.)*'"), "''");
  clean = clean.replaceAll(RegExp(r'"(?:[^"\r\n\\]|\\.)*"'), '""');

  // 4. Single-line comments //
  clean = clean.replaceAll(RegExp(r'//[^\r\n]*'), '');

  return clean;
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
