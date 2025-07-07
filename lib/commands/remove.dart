import 'dart:io';
import '../utils/config_utils.dart';
import '../utils/gradle_utils.dart';
import '../utils/ios_utils.dart';

Future<void> runRemove() async {
  print('\n⚠️  This will remove all flavor configuration.');
  print('\n📋 What will happen:');
  print('  • All flavor folders and configuration files will be deleted');
  print('  • Your Xcode project will be restored to its original state');
  print('  • Any changes made in Xcode after flavor setup will be lost');
  print('  • Your original GoogleService-Info.plist will be restored');
  print('\n💡 Tip: Make sure to commit your Xcode changes before proceeding if you want to keep them.');
  print('\n🔄 You can always re-run the setup command to add flavors back later.');

  stdout.write('\nProceed with removal? (y/n): ');
  final confirm = stdin.readLineSync();
  if (confirm == null || confirm.toLowerCase() != 'y') {
    print('❌ Aborted.');
    return;
  }

  await deleteConfigFile();
  await removeFlavorsFromGradle();
  await removeIOSFlavors();

  final flavorsFolder = Directory('android/app/src/flavors');
  if (await flavorsFolder.exists()) {
    await flavorsFolder.delete(recursive: true);
    print('✅ Deleted android/app/src/flavors folder');
  }

  // Restore default GoogleService-Info.plist from backup if it exists
  final defaultPlist = File('ios/Runner/GoogleService-Info.plist');
  final backupPlist = File('ios/Runner/GoogleService-Info.plist.bak');
  if (await backupPlist.exists()) {
    await backupPlist.rename(defaultPlist.path);
    print('✅ Restored default GoogleService-Info.plist from backup.');
  }

  // Restore original project.pbxproj from backup if it exists
  final pbxprojFile = File('ios/Runner.xcodeproj/project.pbxproj');
  final backupPbxproj = File('ios/Runner.xcodeproj/project.pbxproj.bak');
  if (await backupPbxproj.exists()) {
    await backupPbxproj.rename(pbxprojFile.path);
    print('✅ Restored original project.pbxproj from backup.');
  }

  print('✅ Flavors removed successfully.');

  // Podfile check
  final podfile = File('ios/Podfile');
  if (!podfile.existsSync()) {
    print("\n⚠️  Podfile is missing in ios/. Run 'flutter create .' in your project root to restore it.");
  }
}


