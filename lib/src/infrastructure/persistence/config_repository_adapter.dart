import 'package:dashcn_cli/src/config.dart';
import 'package:dashcn_cli/src/domain/entities/config_model.dart';
import 'package:dashcn_cli/src/domain/repositories/config_repository.dart';

class ConfigRepositoryAdapter implements ConfigRepository {
  final String projectRoot;

  const ConfigRepositoryAdapter({required this.projectRoot});

  @override
  Future<DomainConfigModel> load() async {
    final config = await DashcnConfig.load(projectRoot);
    return DomainConfigModel(
      defaultNamespace: config.effectiveDefaultNamespace,
    );
  }

  @override
  Future<void> save(DomainConfigModel config) async {
    final current = await DashcnConfig.load(projectRoot);
    await DashcnConfig.save(
      projectRoot,
      current.copyWith(defaultNamespace: config.defaultNamespace),
    );
  }
}
