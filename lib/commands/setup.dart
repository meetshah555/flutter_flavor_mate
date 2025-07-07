import 'dart:io';
import 'dart:convert';

import '../utils/config_utils.dart';
import '../utils/gradle_utils.dart';
import '../utils/app_names_utils.dart';
import '../utils/ios_utils.dart';

Future<void> runSetup() async {
  // 1️⃣ Check existing config
  String? savedAppName;
  if (await configFileExists()) {
    final existing = await readRawConfigFile();
    savedAppName = existing?['appName']?.trim();

    if (savedAppName != null && savedAppName.isNotEmpty) {
      stdout.write('\n✅ Found existing app name: "$savedAppName". Use this? (Y/n): ');
      final useExisting = stdin.readLineSync();
      if (useExisting == null || useExisting.trim().toLowerCase() == 'n') {
        savedAppName = null; // force re-entry
      }
    }

    print('⚠️  Existing .flavor_config.json detected. This will overwrite your existing configuration.');
    stdout.write('Do you want to continue? (y/n): ');
    final overwrite = stdin.readLineSync();
    if (overwrite == null || overwrite.toLowerCase() != 'y') {
      print('❌ Aborting setup without changes.');
      return;
    } else {
      await deleteConfigFile();
    }
  }

  // 2️⃣ Show IMPORTANT Firebase warning AFTER overwrite confirmation
  print('\n⚠️  IMPORTANT!');
  print('You need to create Firebase configs for these flavors first.');
  print('After setup, place them here:');
  print('- Android: android/app/src/flavors/<flavor>/google-services.json');
  print('- iOS: ios/Runner/flavors/<flavor>/GoogleService-Info.plist');
  print('\n⚠️  For iOS flavor automation, you must have XcodeGen installed.');
  print('  Install it with: brew install xcodegen');
  print('');
  // Require explicit y/n confirmation
  while (true) {
    stdout.write('Proceed? (y/n): ');
    final proceed = stdin.readLineSync();
    if (proceed != null) {
      final input = proceed.trim().toLowerCase();
      if (input == 'y') {
        break; // proceed
      } else if (input == 'n') {
        print('❌ Setup cancelled.');
        return;
      }
    }
    print('Please enter "y" or "n".');
  }

  // Check if xcodegen is installed before iOS setup
  final xcodegenCheck = await Process.run('which', ['xcodegen']);
  if ((xcodegenCheck.stdout as String).trim().isEmpty) {
    print('❌ XcodeGen is not installed. Please install it with: brew install xcodegen');
    print('Aborting setup.');
    return;
  }

  // 3️⃣ App name detection
  String baseAppName = savedAppName ?? '';

  if (baseAppName.isEmpty) {
    final detectedAppName = await getAndroidAppName();
    if (detectedAppName != null && detectedAppName.trim().isNotEmpty) {
      stdout.write('\n✅ Detected Android app name: "$detectedAppName". Use this? (Y/n): ');
      final useDetected = stdin.readLineSync();
      if (useDetected == null || useDetected.trim().toLowerCase() != 'n') {
        baseAppName = detectedAppName.trim();
      }
    }
  }

  // 4️⃣ Force user input if still empty
  while (baseAppName.isEmpty) {
    stdout.write('\n❗ Enter your base App Name (cannot be blank): ');
    final manualInput = stdin.readLineSync();
    if (manualInput != null && manualInput.trim().isNotEmpty) {
      baseAppName = manualInput.trim();
    } else {
      print('❌ App Name cannot be empty.');
    }
  }

  print('\n✅ Using base app name: "$baseAppName" for all flavors.\n');

  // 5️⃣ Get flavor names
  List<String> flavorNames = [];
  while (true) {
    stdout.write('\nEnter all flavor names separated by commas (e.g. dev,stage,prod): ');
    final flavorsInput = stdin.readLineSync();

    if (flavorsInput == null || flavorsInput.trim().isEmpty) {
      print('❌ No flavors entered. Aborting.');
      return;
    }

    // Split on comma only
    flavorNames = flavorsInput
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    final invalids = flavorNames.where((name) => !isValidFlavorName(name)).toList();

    if (invalids.isEmpty) {
      break;
    }

    print('❌ ERROR: Invalid flavor name(s): ${invalids.join(", ")}');
  }

  print('✅ Flavors accepted: $flavorNames');

  // Create required folders for Android and iOS, and prompt user to add config files
  for (final flavor in flavorNames) {
    // Android
    final androidFlavorDir = Directory('android/app/src/flavors/$flavor');
    if (!androidFlavorDir.existsSync()) {
      androidFlavorDir.createSync(recursive: true);
      print('✅ Created folder: ${androidFlavorDir.path}');
    }
    // iOS
    final iosFlavorDir = Directory('ios/Runner/flavors/$flavor');
    if (!iosFlavorDir.existsSync()) {
      iosFlavorDir.createSync(recursive: true);
      print('✅ Created folder: ${iosFlavorDir.path}');
    }
  }
  print('\n⚠️  Please add the following files for each flavor:');
  for (final flavor in flavorNames) {
    print('  Android: android/app/src/flavors/$flavor/google-services.json');
    print('  iOS: ios/Runner/flavors/$flavor/GoogleService-Info.plist');
  }
  stdout.write('\nPress Enter to continue after you have added all files...');
  stdin.readLineSync();

  // Validate that all required files exist
  bool allFilesExist = true;
  for (final flavor in flavorNames) {
    final androidFile = File('android/app/src/flavors/$flavor/google-services.json');
    final iosFile = File('ios/Runner/flavors/$flavor/GoogleService-Info.plist');
    if (!androidFile.existsSync()) {
      print('❌ Missing: android/app/src/flavors/$flavor/google-services.json');
      allFilesExist = false;
    }
    if (!iosFile.existsSync()) {
      print('❌ Missing: ios/Runner/flavors/$flavor/GoogleService-Info.plist');
      allFilesExist = false;
    }
  }
  if (!allFilesExist) {
    print('\n❌ One or more required files are missing. Aborting setup.');
    return;
  }

  // 6️⃣ Collect config per flavor
  final List<Map<String, dynamic>> allConfigs = [];
  for (var flavorName in flavorNames) {
    print('\n--- Configuring flavor: $flavorName ---');

    bool isProduction = false;
    while (true) {
      stdout.write('Is this the production flavor? (y/n): ');
      final isProdInput = stdin.readLineSync();
      if (isProdInput != null && isProdInput.trim().toLowerCase() == 'y') {
        isProduction = true;
        break;
      } else if (isProdInput != null && isProdInput.trim().toLowerCase() == 'n') {
        isProduction = false;
        break;
      } else {
        print('Please enter "y" or "n".');
      }
    }

    String appIdSuffix = '';
    if (isProduction) {
      print('✅ Production flavor detected. applicationIdSuffix will be empty.');
    } else {
      stdout.write('Enter applicationIdSuffix (e.g. .$flavorName). Leave blank to use default ".$flavorName": ');
      final input = stdin.readLineSync();
      appIdSuffix = (input == null || input.trim().isEmpty) ? '.$flavorName' : input.trim();
    }

    stdout.write('Enter versionNameSuffix (optional): ');
    String? versionNameSuffix = stdin.readLineSync();

    stdout.write('Enter app_name suffix (optional): ');
    String? appNameSuffix = stdin.readLineSync();

    allConfigs.add({
      "flavor": flavorName,
      "isProduction": isProduction,
      "Android": {
        "applicationIdSuffix": appIdSuffix,
        "versionNameSuffix": versionNameSuffix ?? "",
        "appNameSuffix": appNameSuffix ?? "",
        "dimension": "default",
      },
      "iOS": {
        // iOS flavor config collection
        "schemeName": _collectIOSSchemeName(flavorName),
        "bundleIdSuffix": _collectIOSBundleIdSuffix(flavorName, isProduction),
        "displayNameSuffix": _collectIOSDisplayNameSuffix(flavorName),
      },
    });
  }

  // 7️⃣ Preview
  print('\n✅ Preview of all configured flavors:\n');
  for (var config in allConfigs) {
    final flavor = config['flavor'];
    final android = config['Android'];
    final ios = config['iOS'];
    print('- $flavor');
    print('  Android:');
    print('    applicationIdSuffix = "${android['applicationIdSuffix']}"');
    print('    versionNameSuffix = "${android['versionNameSuffix']}"');
    print('    app_name = "$baseAppName ${android['appNameSuffix']}"');
    print('    dimension = "default"\n');
    print('  iOS:');
    print('    schemeName = "${ios['schemeName']}"');
    print('    bundleIdSuffix = "${ios['bundleIdSuffix']}"');
    print('    displayName = "$baseAppName ${ios['displayNameSuffix']}"\n');
  }

  // Validation: At least one production flavor
  final hasProduction = allConfigs.any((c) => c['isProduction'] == true);
  if (!hasProduction) {
    print('\n❌ You must mark at least one flavor as production. Aborting setup.');
    return;
  }

  // Require explicit y/n confirmation
  while (true) {
    stdout.write('Proceed with saving this configuration? (y/n): ');
    final confirmAll = stdin.readLineSync();
    if (confirmAll != null) {
      final input = confirmAll.trim().toLowerCase();
      if (input == 'y') {
        break; // proceed
      } else if (input == 'n') {
        print('❌ Aborting setup. No changes were made.');
        return;
      }
    }
    print('Please enter "y" or "n".');
  }

  // 8️⃣ Save config (including appName)
  print('\n💾 Creating backups of your original iOS project files...');
  
  // Backup default GoogleService-Info.plist if it exists
  final defaultPlist = File('ios/Runner/GoogleService-Info.plist');
  final backupPlist = File('ios/Runner/GoogleService-Info.plist.bak');
  if (await defaultPlist.exists()) {
    await defaultPlist.rename(backupPlist.path);
    print('✅ Moved default GoogleService-Info.plist to backup.');
  }

  // Backup project.pbxproj if it exists
  final pbxprojFile = File('ios/Runner.xcodeproj/project.pbxproj');
  final backupPbxproj = File('ios/Runner.xcodeproj/project.pbxproj.bak');
  if (await pbxprojFile.exists()) {
    await pbxprojFile.copy(backupPbxproj.path);
    print('✅ Backed up project.pbxproj.');
  }
  
  print('✅ Backups created. Your original project will be restored when you remove flavors.');
  await writeConfigFileWithAppName(baseAppName, allConfigs);
  await updateGradleFlavors(allConfigs, baseAppName);
  await updateIOSFlavors(allConfigs);

  print('\n✅ Flavors have been successfully set up!');

  // Podfile check
  final podfile = File('ios/Podfile');
  if (!podfile.existsSync()) {
    print("\n⚠️  Podfile is missing in ios/. Run 'flutter create .' in your project root to restore it.");
  }
}

// Helper functions for iOS config collection
String _collectIOSSchemeName(String flavorName) {
  stdout.write('Enter iOS scheme name for "$flavorName" (default: $flavorName): ');
  final input = stdin.readLineSync();
  return (input == null || input.trim().isEmpty) ? flavorName : input.trim();
}

String _collectIOSBundleIdSuffix(String flavorName, bool isProduction) {
  if (isProduction) {
    print('✅ Production flavor detected. Bundle ID suffix will be empty.');
    return '';
  }
  stdout.write('Enter iOS bundle ID suffix for "$flavorName" (e.g. .$flavorName, default: .$flavorName): ');
  final input = stdin.readLineSync();
  return (input == null || input.trim().isEmpty) ? '.$flavorName' : input.trim();
}

String _collectIOSDisplayNameSuffix(String flavorName) {
  stdout.write('Enter iOS display name suffix for "$flavorName" (optional): ');
  final input = stdin.readLineSync();
  return (input == null) ? '' : input.trim();
}


