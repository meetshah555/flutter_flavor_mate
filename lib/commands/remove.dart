import 'dart:io';
import '../utils/config_utils.dart';
import '../utils/gradle_utils.dart';

Future<void> runRemove() async {
  print('\n⚠️  This will remove all flavor configuration.');

  stdout.write('Proceed? (y/n): ');
  final confirm = stdin.readLineSync();
  if (confirm == null || confirm.toLowerCase() != 'y') {
    print('❌ Aborted.');
    return;
  }

  await deleteConfigFile();
  await removeFlavorsFromGradle();

  final flavorsFolder = Directory('android/app/src/flavors');
  if (await flavorsFolder.exists()) {
    await flavorsFolder.delete(recursive: true);
    print('✅ Deleted android/app/src/flavors folder');
  }

  print('✅ Flavors removed successfully.');
}
