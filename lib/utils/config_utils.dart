import 'dart:convert';
import 'dart:io';

const configFile = '.flavor_config.json';

/// Check if .flavor_config.json exists
Future<bool> configFileExists() async {
  return File(configFile).exists();
}

/// Write the complete config to .flavor_config.json
Future<void> writeConfigFileWithAppName(String appName, List<Map<String, dynamic>> flavors) async {
  final file = File(configFile);
  final data = {
    "appName": appName,
    "flavors": flavors,
  };
  final jsonData = JsonEncoder.withIndent('  ').convert(data);
  await file.writeAsString(jsonData);
  print('✅ Saved configuration to $configFile');
}

Future<Map<String, dynamic>?> readRawConfigFile() async {
  final file = File(configFile);
  if (!await file.exists()) return null;
  final content = await file.readAsString();
  return jsonDecode(content) as Map<String, dynamic>?;
}

/// Read the config file back into Dart
Future<List<Map<String, dynamic>>> readConfigFile() async {
  final file = File(configFile);
  if (!await file.exists()) {
    throw Exception('❌ No $configFile found in project root.');
  }
  final content = await file.readAsString();
  final List<dynamic> parsed = jsonDecode(content);
  return List<Map<String, dynamic>>.from(parsed);
}

/// Delete the config file
Future<void> deleteConfigFile() async {
  final file = File(configFile);
  if (await file.exists()) {
    await file.delete();
    print('✅ Deleted $configFile');
  }
}

/// Capitalize a string (utility)
String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// Validate flavor name (only letters/numbers/underscores, cannot start with number)
bool isValidFlavorName(String name) {
  final validPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
  return validPattern.hasMatch(name);
}
