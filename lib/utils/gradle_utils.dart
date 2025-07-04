import 'dart:io';

Future<void> updateGradleFlavors(List<Map<String, dynamic>> configs,String baseAppName) async {
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

String _generateGroovyFlavors(List<Map<String, dynamic>> configs,String baseAppName) {
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

String _generateKotlinFlavors(List<Map<String, dynamic>> configs,String baseAppName) {
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

Future<void> _updateGroovyGradle(File file, List<Map<String, dynamic>> configs,String baseAppName) async {
  var content = await file.readAsString();
  final flavorBlock = _generateGroovyFlavors(configs,baseAppName);

  if (content.contains('productFlavors')) {
    content = _replaceProductFlavors(content, flavorBlock);
  } else {
    content = _insertAfterAndroidBlock(content, flavorBlock);
  }

  await file.writeAsString(content);
  print('✅ [Android] build.gradle updated successfully.');
}

Future<void> _updateKotlinGradle(File file, List<Map<String, dynamic>> configs,String baseAppName) async {
  var content = await file.readAsString();
  final flavorBlock = _generateKotlinFlavors(configs,baseAppName);

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
  final indentedNewBlock = newBlock
      .split('\n')
      .map((line) => line.isNotEmpty ? '$indent$line' : line)
      .join('\n');

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






