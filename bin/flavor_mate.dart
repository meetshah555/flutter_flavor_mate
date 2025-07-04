import 'package:args/args.dart';
import 'package:flavor_mate/commands/remove.dart';
import 'package:flavor_mate/commands/setup.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addCommand('setup')
    ..addCommand('remove');

  final results = parser.parse(arguments);

  if (results['help'] || results.arguments.isEmpty) {
    print('''
🍹  Flavor Mate - Flutter Flavors CLI

Usage:
  dart run flavor_mate <command>

Available commands:
  setup      Interactive flavor setup

Options:
${parser.usage}
''');
    return;
  }

  final command = results.command?.name;
  switch (command) {
    case 'setup':
      await runSetup();
      break;
    case 'remove':
      await runRemove();
      break;
    default:
      print('❌ Unknown command: $command');
      print(parser.usage);
  }
}
