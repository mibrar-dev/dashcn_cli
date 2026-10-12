import 'package:dashcn_cli/src/domain/entities/state_model.dart';

abstract class StateRepository {
  Future<DomainStateModel> load();
  Future<void> save(DomainStateModel state);
}
