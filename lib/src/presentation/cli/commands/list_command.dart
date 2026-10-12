import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/catalog_entry.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn list [--blocks] [--flows] [--category <c>] [--json]`: every
/// component (default), every block or every flow in the registry manifest,
/// grouped by category (P5_CLI_PLAN.md §2, P6-B2, P9-3b).
///
/// The JSON envelope always carries `components`, `blocks` and `flows`: the
/// ones that are not on show are empty arrays, so a consumer never has to
/// probe for a key.
Future<int> runListCommand({
  required ArgResults listCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(listCommand, 'json');
  final showBlocks = commandFlag(listCommand, 'blocks');
  final showFlows = commandFlag(listCommand, 'flows');
  final category = commandOption(listCommand, 'category');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(listCommand, 'help')) {
    stdout.writeln('Usage: dashcn list [--blocks] [--flows] '
        '[--category <c>] [--json]');
    stdout.writeln('');
    stdout.writeln(
        'Lists components (default), blocks or flows, grouped by category.');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln('  --blocks           List the blocks layer instead');
    stdout.writeln('  --flows            List the flows layer instead');
    stdout.writeln('  --category <name>  Only entries of that category');
    stdout.writeln('  --json             Machine-readable output on stdout');
    return ExitCodes.success;
  }
  if (showBlocks && showFlows) {
    logger.errorToStderr(
      'Error: --blocks and --flows cannot be combined.',
    );
    return ExitCodes.usage;
  }

  try {
    final context = await CommandContextResolver.resolve(
      projectRoot: projectRoot,
      logger: logger,
      registryOverride: registryOverride,
      offline: offline,
    );
    final manifest = context.loadedManifest.manifest;
    final components = filterByCategory(
      [
        for (final component in manifest.components.values)
          CatalogEntry.component(component),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));
    final blocks = filterByCategory(
      [
        for (final block in manifest.blocks.values) CatalogEntry.block(block),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));
    final flows = filterByCategory(
      [
        for (final flow in manifest.flows.values) CatalogEntry.flow(flow),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));
    final kind = showFlows
        ? CatalogKind.flow
        : (showBlocks ? CatalogKind.block : CatalogKind.component);
    final shown = showFlows ? flows : (showBlocks ? blocks : components);

    if (json) {
      printJson(jsonEnvelope(
        command: 'list',
        data: {
          'registry': manifest.registry.name,
          'kind': kind.name,
          'count': shown.length,
          'categories': categorySummary(shown),
          'components': kind == CatalogKind.component ? components : const [],
          'blocks': kind == CatalogKind.block ? blocks : const [],
          'flows': kind == CatalogKind.flow ? flows : const [],
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }

    if (shown.isEmpty) {
      final wanted = category?.trim();
      if (wanted != null && wanted.isNotEmpty) {
        stdout.writeln('No ${kind.name}s in category "$wanted".');
        // The taxonomies are independent, so an empty result is usually the
        // wrong list.
        final others = [
          if (kind != CatalogKind.component && components.isNotEmpty)
            '`list` for components',
          if (kind != CatalogKind.block && blocks.isNotEmpty)
            '`list --blocks` for blocks',
          if (kind != CatalogKind.flow && flows.isNotEmpty)
            '`list --flows` for flows',
        ];
        if (others.isNotEmpty) {
          stdout.writeln('Try ${others.join(', ')} for the other catalogs.');
        }
      } else {
        stdout.writeln('No ${kind.name}s in this registry.');
      }
      return ExitCodes.success;
    }
    stdout.writeln('${shown.length} ${kind.name}(s) by category:');
    writeGroupedCatalog(shown, write: stdout.writeln);
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
