import 'dart:io';
import 'package:xcodeproj/xcodeproj.dart';
import 'package:path/path.dart' as p;

Future<void> updateIOSFlavors(List<Map<String, dynamic>> configs) async {
  print('✅ [iOS] Applying XcodeGen flavor configuration...');

  final iosDir = Directory('ios');
  if (!iosDir.existsSync()) {
    print('❌ iOS directory not found. Skipping iOS configuration.');
    return;
  }

  // 1. Create flavor folders and dummy plist
  for (final config in configs) {
    final flavor = config['flavor'];
    final flavorDir = Directory(p.join('ios', 'Runner', 'flavors', _capitalize(flavor)));
    if (!flavorDir.existsSync()) {
      flavorDir.createSync(recursive: true);
      print('✅ Created folder: ${flavorDir.path}');
    }
    final plistPath = p.join(flavorDir.path, 'GoogleService-Info.plist');
    if (!File(plistPath).existsSync()) {
      File(plistPath).writeAsStringSync(_dummyPlistContent);
      print('✅ Created dummy plist: $plistPath');
    }
  }

  final projectYmlPath = p.join('ios', 'project.yml');
  final ymlContent = _generateProjectYml(configs);
  await File(projectYmlPath).writeAsString(ymlContent);
  print('✅ Generated ios/project.yml');

  // Run XcodeGen
  final result = await Process.run('xcodegen', ['generate', '--spec', 'ios/project.yml', '--project', 'ios']);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode == 0) {
    print('✅ XcodeGen ran successfully.');
    await _removePlistFromCopyBundleResources();
    print('✅ Removed GoogleService-Info.plist from Copy Bundle Resources in project.pbxproj.');
  } else {
    print('❌ XcodeGen failed.');
  }
  print('\n🔔 After setup, run:'
        '\n   flutter pub get'
        '\n   cd ios && pod install && cd ..'
        '\nThen open ios/Runner.xcworkspace in Xcode.');
}

Future<void> _removePlistFromCopyBundleResources() async {
  final pbxprojFile = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!await pbxprojFile.exists()) return;
  final lines = await pbxprojFile.readAsLines();

  // Step 1: Find all PBXBuildFile IDs for GoogleService-Info.plist
  final buildFileIdRegex = RegExp(r'\s*([A-F0-9]+) /\* GoogleService-Info.plist in Resources \*/ = \{isa = PBXBuildFile;[^}]*\};');
  final buildFileIds = <String>{};
  for (final line in lines) {
    final match = buildFileIdRegex.firstMatch(line);
    if (match != null) {
      buildFileIds.add(match.group(1)!);
    }
  }

  // Step 2: Remove PBXBuildFile entries for GoogleService-Info.plist
  final filteredLines = <String>[];
  for (final line in lines) {
    if (buildFileIdRegex.hasMatch(line)) continue; // skip
    filteredLines.add(line);
  }

  // Step 3: Remove references to those IDs in PBXResourcesBuildPhase sections
  final idRefRegex = RegExp(buildFileIds.map((id) => RegExp.escape(id)).join('|'));
  final finalLines = <String>[];
  for (final line in filteredLines) {
    // Remove lines that reference the build file IDs in files = (...)
    if (idRefRegex.pattern.isNotEmpty && idRefRegex.hasMatch(line)) continue;
    finalLines.add(line);
  }

  await pbxprojFile.writeAsString(finalLines.join('\n'));
}

Future<void> removeIOSFlavors() async {
  // Remove iOS flavors folder
  final iosFlavorsFolder = Directory('ios/Runner/flavors');
  if (await iosFlavorsFolder.exists()) {
    await iosFlavorsFolder.delete(recursive: true);
    print('✅ Deleted ios/Runner/flavors folder');
  }

  // Remove iOS project.yml
  final projectYmlPath = p.join('ios', 'project.yml');
  if (await File(projectYmlPath).exists()) {
    await File(projectYmlPath).delete();
    print('✅ Deleted ios/project.yml');
  }
  // Note: We do NOT regenerate the Xcode project here
  // The original project.pbxproj will be restored from backup in the remove command
}

String _generateProjectYml(List<Map<String, dynamic>> configs) {
  final buffer = StringBuffer();
  buffer.writeln('name: Runner');
  buffer.writeln('configs:');
  for (final config in configs) {
    final flavor = config['flavor'];
    buffer.writeln('  Debug-$flavor: debug');
    buffer.writeln('  Release-$flavor: release');
  }
  buffer.writeln('settings:');
  buffer.writeln('  base:');
  buffer.writeln('    PRODUCT_BUNDLE_IDENTIFIER: com.example.runner');
  buffer.writeln('targets:');
  buffer.writeln('  Runner:');
  buffer.writeln('    type: application');
  buffer.writeln('    platform: iOS');
  buffer.writeln('    sources: [Runner]');
  buffer.writeln('    settings:');
  buffer.writeln('      configs:');
  for (final config in configs) {
    final flavor = config['flavor'];
    final ios = config['iOS'];
    buffer.writeln('        Debug-$flavor:');
    buffer.writeln('          PRODUCT_BUNDLE_IDENTIFIER: com.example.runner${ios['bundleIdSuffix']}');
    buffer.writeln('          PRODUCT_NAME: Runner ${ios['displayNameSuffix']}');
    buffer.writeln('          GOOGLE_SERVICE_INFO_PLIST_PATH: Runner/flavors/$flavor/GoogleService-Info.plist');
    buffer.writeln('        Release-$flavor:');
    buffer.writeln('          PRODUCT_BUNDLE_IDENTIFIER: com.example.runner${ios['bundleIdSuffix']}');
    buffer.writeln('          PRODUCT_NAME: Runner ${ios['displayNameSuffix']}');
    buffer.writeln('          GOOGLE_SERVICE_INFO_PLIST_PATH: Runner/flavors/$flavor/GoogleService-Info.plist');
  }
  buffer.writeln('    preBuildScripts:');
  buffer.writeln('      - name: Copy GoogleService-Info.plist');
  buffer.writeln('        script: |');
  buffer.writeln('          FLAVOR=\$(echo "\${CONFIGURATION}" | sed -E "s/^(Debug|Release)-//")');
  buffer.writeln('          PLIST_PATH="\${SRCROOT}/Runner/flavors/\${FLAVOR}/GoogleService-Info.plist"');
  buffer.writeln('          if [ -f "\$PLIST_PATH" ]; then');
  buffer.writeln('            cp "\$PLIST_PATH" "\${BUILT_PRODUCTS_DIR}/\${PRODUCT_NAME}.app/GoogleService-Info.plist"');
  buffer.writeln('          else');
  buffer.writeln('            echo "warning: GoogleService-Info.plist for flavor \$FLAVOR not found!"');
  buffer.writeln('          fi');
  buffer.writeln('    # Note: GoogleService-Info.plist is NOT included in resources to avoid "Multiple commands produce" error. The plist is copied via the preBuildScript above');
  buffer.writeln('schemes:');
  for (final config in configs) {
    final flavor = config['flavor'];
    buffer.writeln('  $flavor:');
    buffer.writeln('    build:');
    buffer.writeln('      targets:');
    buffer.writeln('        Runner: all');
    buffer.writeln('    run:');
    buffer.writeln('      config: Debug-$flavor');
  }
  return buffer.toString();
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const _dummyPlistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Dummy</key>
  <string>Replace this file with your real GoogleService-Info.plist</string>
</dict>
</plist>
''';
