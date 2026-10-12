import 'package:dashcn_cli/src/domain/value_objects/component_ref.dart';

abstract class AddResolutionPolicy {
  ComponentRef resolve(String rawToken);
}
