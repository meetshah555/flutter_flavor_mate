import 'dart:io';
import 'package:xml/xml.dart';

Future<String?> getAndroidAppName() async {
  final file = File('android/app/src/main/res/values/strings.xml');
  if (!await file.exists()) return null;

  try {
    final content = await file.readAsString();
    final document = XmlDocument.parse(content);

    final appNameNode = document
        .findAllElements('string')
        .firstWhere(
          (element) => element.getAttribute('name') == 'app_name',
      orElse: () => XmlElement(XmlName('string')),
    );

    final value = appNameNode.value?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  } catch (e) {
    print('⚠️  Could not parse app name from strings.xml: $e');
    return null;
  }
}
