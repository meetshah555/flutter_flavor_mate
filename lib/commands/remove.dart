import 'dart:io';
import 'dart:convert';
import '../utils/config_utils.dart';
import '../utils/gradle_utils.dart';
import '../utils/ios_utils.dart';

Future<void> runRemove() async {
  print('\n⚠️  This will remove all flavor configuration.');
  print('\n📋 What will happen:');
  print('  • All flavor folders and configuration files will be deleted');
  print('  • Your Xcode project will be restored to its original state');
  print('  • Android flavor configurations will be removed');
  print('  • You can choose to keep one flavor as the default configuration');
  print('\n💡 Tip: The script creates automatic backups before making changes.');
  print('\n🔄 You can always re-run the setup command to add flavors back later.');

  stdout.write('\nProceed with removal? (y/n): ');
  final confirm = stdin.readLineSync();
  if (confirm == null || confirm.toLowerCase() != 'y') {
    print('❌ Aborted.');
    return;
  }

  // Get available flavors from iOS directory
  final availableFlavors = await _getAvailableFlavors();

  String? flavorToKeep;

  if (availableFlavors.isNotEmpty) {
    print('\n📱 Available flavors: ${availableFlavors.join(', ')}');

    // Ask which flavor to keep or press Enter for complete removal
    stdout.write('\nWhich flavor would you like to keep as default? (press Enter to remove all): ');
    final flavorInput = stdin.readLineSync();
    final selectedFlavor = flavorInput?.trim();

    if (selectedFlavor != null && selectedFlavor.isNotEmpty) {
      // Validate the flavor exists
      if (!availableFlavors.contains(selectedFlavor)) {
        print('❌ ERROR: Flavor "$selectedFlavor" does not exist.');
        print('ℹ️  Available flavors: ${availableFlavors.join(', ')}');
        return;
      }

      flavorToKeep = selectedFlavor;
      print('\n✅ Will keep "$selectedFlavor" as the default configuration.');
      print('✅ All other flavors will be removed.');
    } else {
      print('\n✅ Will remove all flavors and restore to original state.');
      flavorToKeep = null; // Explicitly set to null for complete removal
    }
  } else {
    print('\n📝 No flavors detected. Performing complete cleanup...');
    flavorToKeep = null;
  }

  // Perform the cleanup/removal based on the selected option
  if (flavorToKeep != null && flavorToKeep.isNotEmpty) {
    // Keep one flavor as default, remove all others
    await _keepFlavorAsDefault(flavorToKeep, availableFlavors);
  } else {
    // Remove all flavors and restore to original state
    await _removeAllFlavorsAndRestoreOriginal();
  }

  // Final cleanup
  await _performFinalCleanup();

  // Success message
  if (flavorToKeep != null && flavorToKeep.isNotEmpty) {
    print('\n🎉 Success! "$flavorToKeep" is now your default configuration.');
    print('✅ All other flavors have been removed.');
  } else {
    print('\n🎉 Success! All flavors removed and restored to original state.');
  }

  print('\n🔧 Next steps:');
  print('  • Run "flutter clean"');
  print('  • Run "flutter pub get"');
  print('  • For iOS: cd ios && pod install && cd ..');
  print('  • Restart your IDE/Xcode to see all changes');
}

Future<void> _removeAllFlavorsAndRestoreOriginal() async {
  print('\n🔄 Removing all flavors and restoring to original state...');

  // Android cleanup - remove all flavors completely
  await _performAndroidCleanup();

  // iOS cleanup - remove all flavors completely (pass null for complete removal)
  await removeIOSFlavors(null);

  print('✅ All flavors removed, restored to original state');
}

Future<void> _keepFlavorAsDefault(String flavorToKeep, List<String> allFlavors) async {
  print('\n🔄 Keeping "$flavorToKeep" as default and removing other flavors...');

  // Android cleanup - remove all flavors from gradle, then set up the kept flavor as default
  await _performAndroidCleanupWithDefault(flavorToKeep);

  // iOS cleanup - keep the specified flavor as default
  await removeIOSFlavors(flavorToKeep);

  print('✅ Cleanup completed with "$flavorToKeep" as default');
}

/*Future<void> _removeAllFlavorsAndRestoreNormal() async {
  print('\n🔄 Removing all flavors and restoring to normal setup...');

  // Android cleanup - remove all flavors completely
  await _performAndroidCleanup();

  // iOS cleanup - remove all flavors completely
  await removeIOSFlavors("");

  print('✅ All flavors removed, restored to normal setup');
}*/

Future<void> _performAndroidCleanupWithDefault(String defaultFlavor) async {
  print('\n🤖 Setting up Android with "$defaultFlavor" as default...');

  // First, we need to get the flavor configuration before cleaning up
  final flavorConfig = await _getFlavorConfiguration(defaultFlavor);

  if (flavorConfig == null) {
    print('⚠️  Could not find configuration for "$defaultFlavor". Performing normal cleanup...');
    await _performAndroidCleanup();
    return;
  }

  // Delete config file
  await deleteConfigFile();

  // Set up the selected flavor as the main Android configuration
  await setupAndroidFlavorAsDefault(defaultFlavor, flavorConfig);

  print('✅ Android configured with "$defaultFlavor" as default');
}

Future<Map<String, dynamic>?> _getFlavorConfiguration(String flavorName) async {
  // Try to read from existing configuration files
  final configFile = File('flavor_configs.json');
  if (await configFile.exists()) {
    try {
      final content = await configFile.readAsString();
      final List<dynamic> configs = jsonDecode(content);

      for (final config in configs) {
        if (config['flavor'] == flavorName) {
          return config as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print('⚠️  Could not read flavor configuration: $e');
    }
  }

  // If no config file exists, create a basic default configuration
  return {
    'flavor': flavorName,
    'Android': {
      'applicationIdSuffix': '.${flavorName.toLowerCase()}',
      'versionNameSuffix': '-${flavorName.toLowerCase()}',
      'appNameSuffix': flavorName.toUpperCase(),
    },
    'baseAppName': 'App' // Default base app name
  };
}

Future<List<String>> _getAvailableFlavors() async {
  final flavors = <String>[];

  // Check iOS flavors directory
  final iosFlavorDir = Directory('ios/Runner/flavors');
  if (await iosFlavorDir.exists()) {
    await for (final entity in iosFlavorDir.list()) {
      if (entity is Directory) {
        final flavorName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        flavors.add(flavorName);
      }
    }
  }

  return flavors;
}

Future<void> _performAndroidCleanup() async {
  print('\n🤖 Cleaning up Android configuration...');

  // Delete config file
  await deleteConfigFile();

  // Remove flavors from gradle
  await removeFlavorsFromGradle();

  // Remove flavors folder
  final flavorsFolder = Directory('android/app/src/flavors');
  if (await flavorsFolder.exists()) {
    await flavorsFolder.delete(recursive: true);
    print('✅ Deleted android/app/src/flavors folder');
  }

  print('✅ Android cleanup completed');
}

Future<void> _performFinalCleanup() async {
  print('\n🧹 Performing final cleanup...');

  // Remove temporary files if they exist
  final tempFiles = [
    'ios/flavor_configs.json',
    'flavor_configs.json',
  ];

  for (final filePath in tempFiles) {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      print('✅ Removed temporary file: $filePath');
    }
  }

  // Check Podfile
  final podfile = File('ios/Podfile');
  if (!await podfile.exists()) {
    print("\n⚠️  Podfile is missing in ios/. Run 'flutter create .' in your project root to restore it.");
  }
}