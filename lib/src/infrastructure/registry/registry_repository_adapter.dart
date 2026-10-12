import 'package:dashcn_cli/src/domain/entities/registry_entry.dart';
import 'package:dashcn_cli/src/domain/repositories/registry_repository.dart';
import 'package:dashcn_cli/src/logger.dart';
import 'package:dashcn_cli/src/registry_directory.dart';
import 'package:dashcn_cli/src/version_manager.dart';

class RegistryRepositoryAdapter implements RegistryRepository {
  final String projectRoot;
  final bool offline;
  final String directoryUrl;
  final String? directoryPath;
  final CliLogger logger;
  final RegistryDirectoryClient client;

  RegistryRepositoryAdapter({
    required this.projectRoot,
    required this.offline,
    required this.directoryUrl,
    required this.logger,
    this.directoryPath,
    RegistryDirectoryClient? client,
  }) : client = client ?? RegistryDirectoryClient();

  @override
  Future<List<DomainRegistryEntry>> listRegistries() async {
    final directory = await client.load(
      projectRoot: projectRoot,
      directoryUrl: directoryUrl,
      directoryPath: directoryPath,
      offline: offline,
      currentCliVersion: VersionManager.currentVersion,
      logger: logger,
    );
    return directory.registries
        .map(
          (entry) => DomainRegistryEntry(
            namespace: entry.namespace,
            baseUrl: entry.baseUrl,
          ),
        )
        .toList();
  }
}
