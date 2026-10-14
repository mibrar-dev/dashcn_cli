import 'dart:io';

import 'package:args/args.dart';
import 'package:dashcn_cli/src/exit_codes.dart';
import 'package:dashcn_cli/src/json_output.dart';
import 'package:dashcn_cli/src/presentation/cli/catalog_entry.dart';
import 'package:dashcn_cli/src/presentation/cli/command_context.dart';
import 'package:dashcn_cli/src/presentation/cli/command_support.dart';

/// `dashcn search <query> [--category <c>] [--json]`:
/// case-insensitive match over component, block and flow id, name,
/// description and tags (P5_CLI_PLAN.md §2, P6-B2, P9-3b).
///
/// All kinds are searched at once, because `add <id>` resolves all: a query
/// that names a flow is exactly as useful as one that names a component.
Future<int> runSearchCommand({
  required ArgResults searchCommand,
  required ArgResults rootArgs,
  required String projectRoot,
  String? registryOverride,
  bool offline = false,
}) async {
  final json = commandFlag(searchCommand, 'json');
  final category = commandOption(searchCommand, 'category');
  final logger = commandLogger(rootArgs, json: json);

  if (commandFlag(searchCommand, 'help')) {
    stdout.writeln('Usage: dashcn search <query> '
        '[--category <c>] [--json]');
    stdout.writeln('');
    stdout.writeln('Searches component, block and flow id, name, description '
        'and tags.');
    stdout.writeln('');
    stdout.writeln('Options:');
    stdout.writeln('  --category <name>  Only entries of that category');
    stdout.writeln('  --json             Machine-readable output on stdout');
    return ExitCodes.success;
  }

  final query = searchCommand.rest.join(' ').trim().toLowerCase();
  if (query.isEmpty) {
    stdout.writeln('Usage: dashcn search <query>');
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
    final matches = filterByCategory(
      [
        for (final component in manifest.components.values)
          if (CatalogEntry.component(component).matches(query))
            CatalogEntry.component(component),
        for (final block in manifest.blocks.values)
          if (CatalogEntry.block(block).matches(query))
            CatalogEntry.block(block),
        for (final flow in manifest.flows.values)
          if (CatalogEntry.flow(flow).matches(query)) CatalogEntry.flow(flow),
      ],
      category,
    )..sort((a, b) => a.id.compareTo(b.id));

    if (json) {
      printJson(jsonEnvelope(
        command: 'search',
        data: {
          'query': query,
          'count': matches.length,
          'categories': categorySummary(matches),
          'components': [
            for (final match in matches)
              if (match.kind == CatalogKind.component) match.toJson(),
          ],
          'blocks': [
            for (final match in matches)
              if (match.kind == CatalogKind.block) match.toJson(),
          ],
          'flows': [
            for (final match in matches)
              if (match.kind == CatalogKind.flow) match.toJson(),
          ],
        },
        meta: {'exitCode': ExitCodes.success},
      ));
      return ExitCodes.success;
    }
    if (matches.isEmpty) {
      final wanted = category?.trim();
      final scope =
          wanted == null || wanted.isEmpty ? '' : ' in category "$wanted"';
      stdout.writeln('No components, blocks or flows match "$query"$scope.');
      return ExitCodes.success;
    }
    stdout.writeln('${matches.length} match(es) for "$query":');
    for (final match in matches) {
      final label = match.kind.name;
      stdout.writeln('  ${match.id.padRight(28)} [${match.category} · $label] '
          '${match.description}');
    }
    return ExitCodes.success;
  } catch (error) {
    return reportCommandError(error, logger);
  }
}
