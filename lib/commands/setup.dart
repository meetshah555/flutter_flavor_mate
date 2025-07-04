import 'dart:io';
import 'dart:convert';

import '../utils/config_utils.dart';
import '../utils/gradle_utils.dart';
import '../utils/app_names_utils.dart';

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
  print('You need to create Firebase configs for these flavors first.\n');
  print('After setup, place them here:');
  print('- Android: android/app/src/flavors/<flavor>/google-services.json\n');
  stdout.write('Proceed? (y/n): ');
  final proceed = stdin.readLineSync();
  if (proceed == null || proceed.toLowerCase() != 'y') {
    print('❌ Setup cancelled.');
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
    });
  }

  // 7️⃣ Preview
  print('\n✅ Preview of all configured flavors:\n');
  for (var config in allConfigs) {
    final flavor = config['flavor'];
    final android = config['Android'];
    print('- $flavor');
    print('  Android:');
    print('    applicationIdSuffix = "${android['applicationIdSuffix']}"');
    print('    versionNameSuffix = "${android['versionNameSuffix']}"');
    print('    app_name = "$baseAppName ${android['appNameSuffix']}"');
    print('    dimension = "default"\n');
  }

  stdout.write('Proceed with saving this configuration? (y/n): ');
  final confirmAll = stdin.readLineSync();
  if (confirmAll == null || confirmAll.toLowerCase() != 'y') {
    print('❌ Aborting setup. No changes were made.');
    return;
  }

  // 8️⃣ Save config (including appName)
  await writeConfigFileWithAppName(baseAppName, allConfigs);
  await updateGradleFlavors(allConfigs, baseAppName);

  print('\n✅ Flavors have been successfully set up!');
  print('⚠️  Reminder: Don\'t forget to place your Firebase config files in:');
  print('  - Android: android/app/src/flavors/<flavor>/google-services.json');
}
