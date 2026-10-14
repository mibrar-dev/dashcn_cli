import 'package:dashcn_cli/src/presentation/cli/cli_command_entry.dart';

class CliCommandCategory {
  final String name;
  final List<CliCommandEntry> commands;

  const CliCommandCategory(this.name, this.commands);
}
