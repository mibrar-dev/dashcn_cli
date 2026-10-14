import 'package:dashcn_cli/src/domain/entities/config_model.dart';

abstract class ConfigRepository {
  Future<DomainConfigModel> load();
  Future<void> save(DomainConfigModel config);
}
