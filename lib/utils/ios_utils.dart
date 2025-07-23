import 'dart:io';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'dart:isolate';

Future<void> updateIOSFlavors(List<Map<String, dynamic>> configs) async {
  print('✅ [iOS] Applying flavor configuration using Ruby xcodeproj script...');

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
      print('✅ Created folder:  ${flavorDir.path}');
    }
    final plistPath = p.join(flavorDir.path, 'GoogleService-Info.plist');
    if (!File(plistPath).existsSync()) {
      File(plistPath).writeAsStringSync(_dummyPlistContent);
      print('✅ Created dummy plist: $plistPath');
    }
  }

  // Write configs to a temp file for the Ruby script
  final tempFile = File('ios/flavor_configs.json');
  await tempFile.writeAsString(jsonEncode(configs));

  // Use Isolate.resolvePackageUri to get the absolute path to the Ruby script
  final scriptUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flavor_mate/scripts/ios_flavor_setup.rb'),
  );
  if (scriptUri == null) {
    print('❌ Could not resolve the path to ios_flavor_setup.rb in the package.');
    return;
  }
  final rubyScriptPath = scriptUri.toFilePath();

  // Call the Ruby script using the absolute path
  final result = await Process.run(
    'ruby',
    [rubyScriptPath, tempFile.path],
    runInShell: true,
  );

  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    throw Exception('iOS flavor setup failed');
  }

  print('\n🔔 After setup, run:'
      '\n   flutter pub get'
      '\n   cd ios && pod install && cd ..'
      '\nThen open ios/Runner.xcworkspace in Xcode.');
}

/// Remove iOS flavors using the Ruby removal script
///

/// Remove iOS flavors using the Ruby removal script
///
/// [flavorToKeep] - The flavor to keep as default configuration.
/// If null or empty, all flavors will be removed (complete restoration).
Future<void> removeIOSFlavors(String? flavorToKeep) async {
  final iosDir = Directory('ios');
  if (!iosDir.existsSync()) {
    print('❌ iOS directory not found. Skipping iOS flavor removal.');
    return;
  }

  // Check if Runner.xcodeproj exists
  final xcodeproj = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!await xcodeproj.exists()) {
    print('❌ Runner.xcodeproj not found. Skipping iOS flavor removal.');
    return;
  }

  // Get available flavors first to validate
  final availableFlavors = await getAvailableIOSFlavors();
  if (availableFlavors.isEmpty) {
    print('❌ No flavors found in the project. Nothing to remove.');
    return;
  }

  print('✅ [iOS] Available flavors: ${availableFlavors.join(', ')}');

  // Validate flavor choice if provided
  if (flavorToKeep != null && flavorToKeep.isNotEmpty) {
    if (!availableFlavors.contains(flavorToKeep)) {
      print('❌ Invalid flavor name: "$flavorToKeep"');
      print('❌ Available flavors: ${availableFlavors.join(', ')}');
      return;
    }
    print('✅ [iOS] Keeping "$flavorToKeep" as default configuration and removing all other flavors...');
  } else {
    print('✅ [iOS] Removing all flavor configurations and restoring to original state...');
  }

  // Resolve absolute path to the Ruby removal script in the package
  final scriptUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flavor_mate/scripts/ios_flavor_removal.rb'),
  );

  if (scriptUri == null) {
    print('❌ Could not resolve the path to ios_flavor_removal.rb in the package.');
    return;
  }

  final rubyScriptPath = scriptUri.toFilePath();

  // Verify Ruby script exists
  if (!await File(rubyScriptPath).exists()) {
    print('❌ Ruby script not found at: $rubyScriptPath');
    return;
  }

  // Prepare arguments for Ruby script
  final args = <String>[rubyScriptPath];
  if (flavorToKeep != null && flavorToKeep.isNotEmpty) {
    args.add(flavorToKeep);
  }

  try {
    // Call Ruby script with or without flavor argument
    final result = await Process.run(
      'ruby',
      args,
      runInShell: true,
      workingDirectory: Directory.current.path,
    );

    // Output the results
    if (result.stdout.toString().isNotEmpty) {
      print(result.stdout);
    }
    if (result.stderr.toString().isNotEmpty) {
      stderr.write(result.stderr);
    }

    if (result.exitCode != 0) {
      throw ProcessException(
        'ruby',
        args,
        'iOS flavor removal failed with exit code ${result.exitCode}',
        result.exitCode,
      );
    }

    // CRITICAL FIX: Validate Info.plist exists after removal
    await _validateInfoPlistExists();

    // CRITICAL FIX: Add this line to clean up any remaining references
    await _cleanupRemainingReferences();

    // IMPORTANT: Clean up flavor directories ONLY after Ruby script succeeds
    await _cleanupFlavorDirectories(flavorToKeep);

    print('✅ iOS flavor removal completed successfully');

    // Print next steps
    print('\n🔔 Next steps:');
    print('   1. Run: flutter clean');
    print('   2. Run: cd ios && pod install && cd ..');
    print('   3. Restart Xcode and rebuild your project');

    if (flavorToKeep != null && flavorToKeep.isNotEmpty) {
      print('   4. Your "$flavorToKeep" flavor is now the default configuration');
    } else {
      print('   4. Project restored to original state (no flavors)');
    }

  } catch (e) {
    print('❌ Error during iOS flavor removal: $e');
    rethrow;
  }
}


Future<void> _validateInfoPlistExists() async {
  final infoPlistFile = File('ios/Runner/Info.plist');

  if (!await infoPlistFile.exists()) {
    print('⚠️  Info.plist missing, creating default one...');

    const defaultInfoPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>\$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>\$(PRODUCT_NAME)</string>
	<key>CFBundleExecutable</key>
	<string>\$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>\$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>\$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>\$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
</dict>
</plist>''';

    await infoPlistFile.writeAsString(defaultInfoPlist);
    print('✅ Created default Info.plist');
  }
}

/// Clean up any remaining file references in project.pbxproj
Future<void> _cleanupRemainingReferences() async {
  final pbxprojFile = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!await pbxprojFile.exists()) return;

  String content = await pbxprojFile.readAsString();

  // Remove any remaining flavor directory references
  final flavorRefRegex = RegExp(r'[^\n]*flavors/[^/]+/[^\n]*\n?');
  content = content.replaceAll(flavorRefRegex, '');

  // Clean up empty lines
  content = content.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');

  await pbxprojFile.writeAsString(content);
  print('✅ Cleaned up remaining file references in project.pbxproj');
}


/// Clean up flavor directories after successful removal
Future<void> _cleanupFlavorDirectories(String? flavorToKeep) async {
  final flavorsDir = Directory('ios/Runner/flavors');

  if (!await flavorsDir.exists()) {
    return;
  }

  if (flavorToKeep == null || flavorToKeep.isEmpty) {
    // Remove entire flavors directory if no flavor is kept
    await flavorsDir.delete(recursive: true);
    print('✅ Removed ios/Runner/flavors directory');
  } else {
    // For selective removal, we ALWAYS remove the entire flavors directory
    // because the kept flavor is now set up as the default configuration
    // and its files have been copied to the main Runner directory
    await flavorsDir.delete(recursive: true);
    print('✅ Removed ios/Runner/flavors directory (flavor "$flavorToKeep" is now default configuration)');
  }
}

/// Get list of available flavors from iOS directory
Future<List<String>> getAvailableIOSFlavors() async {
  final flavors = <String>[];
  final flavorsDir = Directory('ios/Runner/flavors');

  if (!await flavorsDir.exists()) {
    return flavors;
  }

  await for (final entity in flavorsDir.list()) {
    if (entity is Directory) {
      final flavorName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      flavors.add(flavorName);
    }
  }

  return flavors..sort();
}

/// Validate if a flavor exists in the iOS configuration
Future<bool> validateIOSFlavor(String flavor) async {
  final availableFlavors = await getAvailableIOSFlavors();
  return availableFlavors.contains(flavor);
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