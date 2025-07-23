import 'dart:io';

Future<void> updateGradleFlavors(List<Map<String, dynamic>> configs, String baseAppName) async {
  print('✅ [Android] Applying Gradle flavor configuration...');

  final groovyFile = File('android/app/build.gradle');
  final kotlinFile = File('android/app/build.gradle.kts');

  if (await groovyFile.exists()) {
    print('✅ Detected Groovy DSL');
    await _updateGroovyGradle(groovyFile, configs, baseAppName);
  } else if (await kotlinFile.exists()) {
    print('✅ Detected Kotlin DSL');
    await _updateKotlinGradle(kotlinFile, configs, baseAppName);
  } else {
    print('⚠️  Could not find build.gradle or build.gradle.kts. Skipping Android flavor configuration.');
    return;
  }

  await _ensureAndroidFlavorSrcFolders(configs);
}

String _generateGroovyFlavors(List<Map<String, dynamic>> configs, String baseAppName) {
  final buffer = StringBuffer();
  buffer.writeln('flavorDimensions "default"');
  buffer.writeln('productFlavors {');
  for (var config in configs) {
    final android = config['Android'];
    final flavorName = config['flavor'];
    buffer.writeln('    $flavorName {');
    buffer.writeln('        dimension "default"');
    buffer.writeln('        applicationIdSuffix "${android['applicationIdSuffix']}"');
    buffer.writeln('        versionNameSuffix "${android['versionNameSuffix']}"');
    buffer.writeln('        resValue "string", "app_name", "$baseAppName ${android['appNameSuffix']}"');
    buffer.writeln('    }');
  }
  buffer.writeln('}');
  return buffer.toString();
}

String _generateKotlinFlavors(List<Map<String, dynamic>> configs, String baseAppName) {
  final buffer = StringBuffer();
  buffer.writeln('flavorDimensions += "default"');
  buffer.writeln('productFlavors {');
  for (var config in configs) {
    final android = config['Android'];
    final flavorName = config['flavor'];
    buffer.writeln('    create("$flavorName") {');
    buffer.writeln('        dimension = "default"');
    buffer.writeln('        applicationIdSuffix = "${android['applicationIdSuffix']}"');
    buffer.writeln('        versionNameSuffix = "${android['versionNameSuffix']}"');
    buffer.writeln('        resValue("string", "app_name", "$baseAppName ${android['appNameSuffix']}")');
    buffer.writeln('    }');
  }
  buffer.writeln('}');
  return buffer.toString();
}

Future<void> _updateGroovyGradle(File file, List<Map<String, dynamic>> configs, String baseAppName) async {
  var content = await file.readAsString();
  final flavorBlock = _generateGroovyFlavors(configs, baseAppName);

  if (content.contains('productFlavors')) {
    content = _replaceProductFlavors(content, flavorBlock);
  } else {
    content = _insertAfterAndroidBlock(content, flavorBlock);
  }

  await file.writeAsString(content);
  print('✅ [Android] build.gradle updated successfully.');
}

Future<void> _updateKotlinGradle(File file, List<Map<String, dynamic>> configs, String baseAppName) async {
  var content = await file.readAsString();
  final flavorBlock = _generateKotlinFlavors(configs, baseAppName);

  if (content.contains('productFlavors')) {
    content = _replaceProductFlavors(content, flavorBlock);
  } else {
    content = _insertAfterAndroidBlock(content, flavorBlock);
  }

  await file.writeAsString(content);
  print('✅ [Android] build.gradle.kts updated successfully.');
}

String _replaceProductFlavors(String content, String newBlock) {
// First clean all old productFlavors blocks
  content = _removeAllProductFlavors(content);

  // Then insert new
  return _insertAfterAndroidBlock(content, newBlock);
}

String _insertAfterAndroidBlock(String content, String newBlock) {
  final androidMatch = RegExp(r'android\s*\{').firstMatch(content);
  if (androidMatch == null) {
    print('❌ ERROR: Could not find "android {" block in build.gradle.kts');
    return content;
  }

  int start = androidMatch.end;
  int braceCount = 1;
  int i = start;
  for (; i < content.length; i++) {
    if (content[i] == '{') braceCount++;
    if (content[i] == '}') braceCount--;
    if (braceCount == 0) break;
  }

  if (braceCount != 0) {
    print('❌ ERROR: Unbalanced braces in android block.');
    return content;
  }

  final androidBlock = content.substring(androidMatch.start, i + 1);

  // Determine indentation of existing android block
  final lines = androidBlock.split('\n');
  String indent = '';
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.isNotEmpty && trimmed != '}' && line.startsWith(RegExp(r'\s'))) {
      indent = line.substring(0, line.indexOf(trimmed));
      break;
    }
  }

  // Prepare newBlock with correct indentation
  final indentedNewBlock = newBlock.split('\n').map((line) => line.isNotEmpty ? '$indent$line' : line).join('\n');

  // Insert before final closing }
  final updatedAndroidBlock = androidBlock.replaceFirst(
    RegExp(r'\}\s*$'),
    '\n$indentedNewBlock\n$indent}',
  );

  return content.replaceRange(androidMatch.start, i + 1, updatedAndroidBlock);
}

Future<void> _ensureAndroidFlavorSrcFolders(List<Map<String, dynamic>> configs) async {
  final parentPath = 'android/app/src/flavors';

  for (var config in configs) {
    final flavorName = config['flavor'];
    final path = '$parentPath/$flavorName';
    final dir = Directory(path);
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
      print('✅ Created Android source folder: $path');
    }
  }
}

String _removeAllProductFlavors(String content) {
  // Remove flavorDimensions lines
  content = content.replaceAll(
    RegExp(r'^\s*flavorDimensions.*$', multiLine: true),
    '',
  );

  // Remove combined flavorDimensions and productFlavors blocks
  content = content.replaceAll(
    RegExp(r'flavorDimensions.*?productFlavors\s*\{[\s\S]*?\}', dotAll: true),
    '',
  );

  // Also remove standalone productFlavors blocks
  content = content.replaceAll(
    RegExp(r'productFlavors\s*\{[\s\S]*?\}', dotAll: true),
    '',
  );

  return content;
}

// For remove command
Future<void> removeFlavorsFromGradle() async {
  final groovyFile = File('android/app/build.gradle');
  final kotlinFile = File('android/app/build.gradle.kts');

  if (await groovyFile.exists()) {
    await _cleanFlavorsFromFile(groovyFile);
  }
  if (await kotlinFile.exists()) {
    await _cleanFlavorsFromFile(kotlinFile);
  }
}

Future<void> _cleanFlavorsFromFile(File file) async {
  String content = await file.readAsString();

  // Remove any top-level flavorDimensions lines
  content = content.replaceAll(
    RegExp(r'^\s*flavorDimensions.*$', multiLine: true),
    '',
  );

  // Find android block
  final androidMatch = RegExp(r'android\s*\{').firstMatch(content);
  if (androidMatch == null) {
    await file.writeAsString(content.trim() + '\n');
    print('✅ Cleaned flavors from ${file.path} (no android block found)');
    return;
  }

  int start = androidMatch.start;
  int braceCount = 0;
  int end = -1;
  for (int i = androidMatch.end - 1; i < content.length; i++) {
    if (content[i] == '{') braceCount++;
    if (content[i] == '}') braceCount--;
    if (braceCount == 0) {
      end = i + 1;
      break;
    }
  }
  if (end == -1) {
    print('❌ ERROR: Could not parse android block.');
    return;
  }

  String androidBlock = content.substring(start, end);

  // Remove any flavorDimensions lines
  androidBlock = androidBlock.replaceAll(
    RegExp(r'^\s*flavorDimensions.*$', multiLine: true),
    '',
  );

  // Remove *all* nested productFlavors blocks
  androidBlock = _removeAllNamedBlocks(androidBlock, 'productFlavors');

  // Remove *all* create() { ... } blocks
  androidBlock = _removeAllCreateBlocks(androidBlock);

  // Remove blank lines
  androidBlock = androidBlock.replaceAll(RegExp(r'\n\s*\n', multiLine: true), '\n');

  // Replace cleaned android block
  content = content.replaceRange(start, end, androidBlock.trim());

  // Final trim
  await file.writeAsString(content.trim() + '\n');
  print('✅ Cleaned flavors from ${file.path}');
}

String _removeAllNamedBlocks(String source, String blockName) {
  while (true) {
    final startMatch = RegExp(r'\b' + blockName + r'\s*\{').firstMatch(source);
    if (startMatch == null) break;

    int start = startMatch.start;
    int braceCount = 0;
    int end = -1;

    for (int i = startMatch.end - 1; i < source.length; i++) {
      if (source[i] == '{') braceCount++;
      if (source[i] == '}') braceCount--;
      if (braceCount == 0) {
        end = i + 1;
        break;
      }
    }

    if (end == -1) break;

    source = source.replaceRange(start, end, '');
  }

  return source;
}

/// Restore Android app to default settings (remove all flavor configurations)
Future<void> restoreDefaultAndroidSettings() async {
  print('✅ [Android] Restoring to default settings...');

  // Remove all flavor configurations from gradle files
  await removeFlavorsFromGradle();

  // Optionally: Clean up flavor-specific source folders
  await _cleanupFlavorSourceFolders();

  print('✅ [Android] Restored to default settings successfully');
}

/// Clean up flavor-specific source folders (optional)
Future<void> _cleanupFlavorSourceFolders() async {
  final flavorSrcDir = Directory('android/app/src/flavors');
  if (await flavorSrcDir.exists()) {
    await flavorSrcDir.delete(recursive: true);
    print('✅ Cleaned up flavor source folders');
  }
}

String _removeAllCreateBlocks(String source) {
  while (true) {
    final startMatch = RegExp(r'create\s*\([^)]*\)\s*\{').firstMatch(source);
    if (startMatch == null) break;

    int start = startMatch.start;
    int braceCount = 0;
    int end = -1;

    for (int i = startMatch.end - 1; i < source.length; i++) {
      if (source[i] == '{') braceCount++;
      if (source[i] == '}') braceCount--;
      if (braceCount == 0) {
        end = i + 1;
        break;
      }
    }

    if (end == -1) break;

    source = source.replaceRange(start, end, '');
  }

  return source;
}

// Add these methods to your existing gradle_utils.dart file
Future<void> setupAndroidFlavorAsDefault(String flavorName, Map<String, dynamic> flavorConfig) async {
  print('🤖 Setting up Android with "$flavorName" as default configuration...');

  // Remove all existing flavor configurations first
  await removeFlavorsFromGradle();

  // Remove flavors folder
  final flavorsFolder = Directory('android/app/src/flavors');
  if (await flavorsFolder.exists()) {
    await flavorsFolder.delete(recursive: true);
    print('✅ Deleted android/app/src/flavors folder');
  }

  // Apply the selected flavor's configuration as the main app configuration
  final android = flavorConfig['Android'];
  final baseAppName = flavorConfig['baseAppName'] ?? 'App';
  await _applyFlavorAsMainConfig(android, baseAppName);

  print('✅ Android configured with "$flavorName" as default');
}

Future<void> _applyFlavorAsMainConfig(Map<String, dynamic> androidConfig, String baseAppName) async {
  final groovyFile = File('android/app/build.gradle');
  final kotlinFile = File('android/app/build.gradle.kts');

  if (await groovyFile.exists()) {
    await _updateMainConfigGroovy(groovyFile, androidConfig, baseAppName);
  } else if (await kotlinFile.exists()) {
    await _updateMainConfigKotlin(kotlinFile, androidConfig, baseAppName);
  } else {
    print('⚠️  Could not find build.gradle or build.gradle.kts. Skipping Android main config update.');
  }
}

Future<void> _updateMainConfigGroovy(File file, Map<String, dynamic> config, String baseAppName) async {
  var content = await file.readAsString();

  // Get current applicationId to build the new one
  final currentAppId = _extractCurrentApplicationId(content);
  final newAppId = currentAppId + config['applicationIdSuffix'];

  // Update applicationId
  content = content.replaceAll(RegExp('applicationId\\s*"[^"]*"|applicationId\\s*\'[^\']*\''), 'applicationId "$newAppId"');

  // Update or add app name resValue
  final newAppName = '$baseAppName ${config['appNameSuffix']}';
  if (content.contains('resValue')) {
    content = content.replaceAll(RegExp('resValue\\s*"string",\\s*"app_name",\\s*"[^"]*"'), 'resValue "string", "app_name", "$newAppName"');
  } else {
    // Add resValue inside defaultConfig block
    content = _addResValueToDefaultConfig(content, newAppName, false);
  }

  await file.writeAsString(content);
  print('✅ Updated build.gradle with new default configuration');
}

Future<void> _updateMainConfigKotlin(File file, Map<String, dynamic> config, String baseAppName) async {
  var content = await file.readAsString();

  // Get current applicationId to build the new one
  final currentAppId = _extractCurrentApplicationId(content);
  final newAppId = currentAppId + config['applicationIdSuffix'];

  // Update applicationId
  content = content.replaceAll(RegExp('applicationId\\s*=\\s*"[^"]*"|applicationId\\s*=\\s*\'[^\']*\''), 'applicationId = "$newAppId"');

  // Update or add app name resValue
  final newAppName = '$baseAppName ${config['appNameSuffix']}';
  if (content.contains('resValue')) {
    content = content.replaceAll(
        RegExp('resValue\\s*\\(\\s*"string",\\s*"app_name",\\s*"[^"]*"\\s*\\)'), 'resValue("string", "app_name", "$newAppName")');
  } else {
    // Add resValue inside defaultConfig block
    content = _addResValueToDefaultConfig(content, newAppName, true);
  }

  await file.writeAsString(content);
  print('✅ Updated build.gradle.kts with new default configuration');
}

String _extractCurrentApplicationId(String content) {
  // Extract current applicationId from the gradle file
  final match = RegExp('applicationId\\s*[=:]\\s*"([^"]+)"').firstMatch(content);
  if (match != null) {
    return match.group(1)!;
  }
  // Try with single quotes
  final singleQuoteMatch = RegExp('applicationId\\s*[=:]\\s*\'([^\']+)\'').firstMatch(content);
  if (singleQuoteMatch != null) {
    return singleQuoteMatch.group(1)!;
  }
  // Default fallback
  return 'com.example.app';
}

String _addResValueToDefaultConfig(String content, String appName, bool isKotlin) {
  // Find defaultConfig block and add resValue
  final defaultConfigMatch = RegExp(r'defaultConfig\s*\{').firstMatch(content);
  if (defaultConfigMatch == null) {
    print('⚠️  Could not find defaultConfig block. App name will not be updated.');
    return content;
  }

  int start = defaultConfigMatch.end;
  int braceCount = 1;
  int end = -1;

  for (int i = start; i < content.length; i++) {
    if (content[i] == '{') braceCount++;
    if (content[i] == '}') braceCount--;
    if (braceCount == 0) {
      end = i;
      break;
    }
  }

  if (end == -1) {
    print('⚠️  Could not parse defaultConfig block. App name will not be updated.');
    return content;
  }

  // Get the indentation
  final lines = content.substring(0, defaultConfigMatch.start).split('\n');
  final lastLine = lines.last;
  final indent = lastLine.replaceAll(RegExp('[^\\s].*'), '') + '        '; // Add extra indentation

  // Add resValue before the closing brace
  final resValueLine =
      isKotlin ? '${indent}resValue("string", "app_name", "$appName")\n' : '${indent}resValue "string", "app_name", "$appName"\n';

  final updatedDefaultConfig = content.substring(defaultConfigMatch.start, end) + '\n$resValueLine$indent';

  return content.replaceRange(defaultConfigMatch.start, end, updatedDefaultConfig);
}
