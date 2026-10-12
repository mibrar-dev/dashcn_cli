import 'package:dashcn_cli/src/domain/entities/state_model.dart';
import 'package:dashcn_cli/src/domain/repositories/state_repository.dart';
import 'package:dashcn_cli/src/state.dart';

class StateRepositoryAdapter implements StateRepository {
  final String projectRoot;
  final String defaultNamespace;

  const StateRepositoryAdapter({
    required this.projectRoot,
    this.defaultNamespace = 'dashcn',
  });

  @override
  Future<DomainStateModel> load() async {
    final state = await DashcnState.load(
      projectRoot,
      defaultNamespace: defaultNamespace,
    );
    return DomainStateModel(
      managedDependencies:
          List<String>.from(state.managedDependencies ?? const <String>[]),
    );
  }

  @override
  Future<void> save(DomainStateModel stateModel) async {
    final current = await DashcnState.load(
      projectRoot,
      defaultNamespace: defaultNamespace,
    );
    await DashcnState.save(
      projectRoot,
      DashcnState(
        installPath: current.installPath,
        sharedPath: current.sharedPath,
        themeId: current.themeId,
        managedDependencies: List<String>.from(stateModel.managedDependencies),
        registries: current.registries,
      ),
    );
  }
}
