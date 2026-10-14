import '../../primitives/form_core/form_core.dart';
import '../../theme/theme.dart';

// Fixture component with a primitive dependency.
class Input {
  const Input();
  FormCore get form => const FormCore();
  Theme get theme => const Theme();
}
