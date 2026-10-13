import 'dart:io';

import 'package:detect_unused_code/detect_unused_code.dart';
import 'package:test/test.dart';

void main() {
  group('Multi-Pubspec & Asset Engine Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('detect_unused_asset_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Flexible Multi-Pubspec Discovery and Parsing', () {
      // Create root package
      final rootPubspec = File('${tempDir.path}/pubspec.yaml');
      rootPubspec.writeAsStringSync('''
name: my_root_app
flutter:
  assets:
    - assets/images/
    - assets/icons/explicit_logo.png
  fonts:
    - family: CustomHeading
      fonts:
        - asset: assets/fonts/Heading.ttf
''');

      // Create a deeply nested internal package
      final nestedPackageDir =
          Directory('${tempDir.path}/custom_modules/features/sub_feature');
      nestedPackageDir.createSync(recursive: true);
      final nestedPubspec = File('${nestedPackageDir.path}/pubspec.yaml');
      nestedPubspec.writeAsStringSync('''
name: sub_feature_pkg
flutter:
  assets:
    - assets/illustrations/banner.webp
''');

      // Discover packages
      final packages = PubspecScanner.scanAllPackages(tempDir);
      expect(packages.length, equals(2));

      final rootPkg = packages.firstWhere((p) => p.name == 'my_root_app');
      expect(rootPkg.declaredAssetPatterns, contains('assets/images/'));
      expect(rootPkg.declaredAssetPatterns,
          contains('assets/icons/explicit_logo.png'));
      expect(rootPkg.declaredFonts['CustomHeading'],
          contains('assets/fonts/Heading.ttf'));

      final subPkg = packages.firstWhere((p) => p.name == 'sub_feature_pkg');
      expect(subPkg.declaredAssetPatterns,
          contains('assets/illustrations/banner.webp'));
    });

    test(
        'Audit assets: detects used, unused, variants, and camelCase identifiers',
        () {
      // 1. Root Pubspec
      final rootPubspec = File('${tempDir.path}/pubspec.yaml');
      rootPubspec.writeAsStringSync('''
name: my_app
flutter:
  assets:
    - assets/images/
    - assets/icons/
''');

      // 2. Asset files
      final usedImg = File('${tempDir.path}/assets/images/logo.png')
        ..createSync(recursive: true);
      usedImg.writeAsStringSync('dummy image content');

      // Resolution variant for used image
      final variant2x = File('${tempDir.path}/assets/images/2.0x/logo.png')
        ..createSync(recursive: true);
      variant2x.writeAsStringSync('variant 2x content');

      // Unused image
      final unusedImg =
          File('${tempDir.path}/assets/images/deprecated_banner.png')
            ..createSync(recursive: true);
      unusedImg.writeAsStringSync('banner content 12345');

      // Generated asset used via CamelCase (icUserAvatar)
      final generatedImg =
          File('${tempDir.path}/assets/icons/ic_user_avatar.svg')
            ..createSync(recursive: true);
      generatedImg.writeAsStringSync('<svg>avatar</svg>');

      // 3. Dart Code referencing assets
      final mainDart = File('${tempDir.path}/lib/main.dart')
        ..createSync(recursive: true);
      mainDart.writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  // Direct path
  Image.asset('assets/images/logo.png');

  // flutter_gen / spider camelCase identifier
  final icon = Assets.icons.icUserAvatar;
}
''');

      // 4. Run AssetAuditor
      final auditor = AssetAuditor(workspaceRoot: tempDir);
      final report = auditor.run();

      expect(report.totalScannedAssets, equals(4));
      // Only deprecated_banner.png should be unused!
      // (logo.png is used, 2.0x/logo.png is a variant of used logo.png, ic_user_avatar.svg is matched via icUserAvatar)
      expect(report.unusedAssets.length, equals(1));
      expect(report.unusedAssets.first.path.replaceAll(r'\', '/'),
          contains('deprecated_banner.png'));
      expect(report.totalReclaimableBytes, greaterThan(0));
    });

    test('Cross-package asset reference auditing', () {
      // Root app
      final rootPubspec = File('${tempDir.path}/pubspec.yaml');
      rootPubspec.writeAsStringSync('''
name: app_root
''');

      // Sub-package in packages/shared_ui
      final subDir = Directory('${tempDir.path}/packages/shared_ui');
      subDir.createSync(recursive: true);
      final subPubspec = File('${subDir.path}/pubspec.yaml');
      subPubspec.writeAsStringSync('''
name: shared_ui
flutter:
  assets:
    - assets/buttons/
''');

      final sharedAsset = File('${subDir.path}/assets/buttons/btn_submit.png')
        ..createSync(recursive: true);
      sharedAsset.writeAsStringSync('btn');

      final unusedShared = File('${subDir.path}/assets/buttons/btn_old.png')
        ..createSync(recursive: true);
      unusedShared.writeAsStringSync('old btn');

      // App references sub-package asset via packages/shared_ui/...
      final appDart = File('${tempDir.path}/lib/app.dart')
        ..createSync(recursive: true);
      appDart.writeAsStringSync('''
void test() {
  final path = 'packages/shared_ui/assets/buttons/btn_submit.png';
}
''');

      final auditor = AssetAuditor(workspaceRoot: tempDir);
      final report = auditor.run();

      expect(report.unusedAssets.length, equals(1));
      expect(report.unusedAssets.first.path.replaceAll(r'\', '/'),
          contains('btn_old.png'));
      expect(report.unusedAssets.first.ownerPackage.name, equals('shared_ui'));
    });

    test(
        'AssetCleaner: deletes unused files, prunes explicit lines in pubspec, creates backup',
        () {
      final rootPubspec = File('${tempDir.path}/pubspec.yaml');
      rootPubspec.writeAsStringSync('''
name: test_cleaner
flutter:
  assets:
    - assets/icons/keep_me.png
    - assets/icons/remove_me.png
''');

      final keepFile = File('${tempDir.path}/assets/icons/keep_me.png')
        ..createSync(recursive: true);
      keepFile.writeAsStringSync('keep');

      final removeFile = File('${tempDir.path}/assets/icons/remove_me.png')
        ..createSync(recursive: true);
      removeFile.writeAsStringSync('remove this file');

      final codeFile = File('${tempDir.path}/lib/main.dart')
        ..createSync(recursive: true);
      codeFile.writeAsStringSync("const img = 'assets/icons/keep_me.png';");

      final auditor = AssetAuditor(workspaceRoot: tempDir);
      final report = auditor.run();

      expect(report.unusedAssets.length, equals(1));
      expect(report.unusedAssets.first.isExplicitInPubspec, isTrue);

      final cleaner = AssetCleaner(workspaceRoot: tempDir);
      final cleanResult = cleaner.clean(unusedAssets: report.unusedAssets);

      expect(cleanResult.deletedFilesCount, equals(1));
      expect(removeFile.existsSync(), isFalse);
      expect(keepFile.existsSync(), isTrue);

      // Verify targeted pubspec.yaml pruning
      final updatedPubspecLines = rootPubspec.readAsLinesSync();
      expect(
          updatedPubspecLines.any((l) => l.contains('remove_me.png')), isFalse);
      expect(updatedPubspecLines.any((l) => l.contains('keep_me.png')), isTrue);

      // Verify backup snapshot created
      expect(cleanResult.backupManifest, isNotNull);
      final backupDir = Directory('${tempDir.path}/.detect_unused/backups');
      expect(backupDir.existsSync(), isTrue);
    });
  });
}
