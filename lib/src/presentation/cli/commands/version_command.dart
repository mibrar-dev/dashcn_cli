import 'package:args/args.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/version_manager.dart';

Future<int> runVersionCommand({
  required ArgResults command,
  required CliLogger logger,
}) async {
  if (command['help'] == true) {
    print('Usage: dashcn version [--check]');
    print('');
    print('Shows the current CLI version.');
    print('');
    print('Options:');
    print('  --check            Check for available updates');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }
  final versionMgr = VersionManager(logger: logger);
  if (command['check'] == true) {
    await versionMgr.checkForUpdates();
  } else {
    versionMgr.showVersion();
  }
  return ExitCodes.success;
}
