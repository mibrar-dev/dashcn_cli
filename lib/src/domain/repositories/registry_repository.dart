import 'package:dashcn_cli/src/domain/entities/registry_entry.dart';

abstract class RegistryRepository {
  Future<List<DomainRegistryEntry>> listRegistries();
}
