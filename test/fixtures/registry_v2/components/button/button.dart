import '../../foundation/data.dart';
import '../../primitives/clickable.dart';
import '../../theme/color_tokens.dart';
import '../../theme/theme.dart';
import 'button_style.dart';

// Fixture component using layer + same-directory imports.
class Button {
  const Button();
  DashcnData get data => const DashcnData();
  Theme get theme => const Theme();
  Clickable get clickable => const Clickable();
  ColorTokens get colors => const ColorTokens();
  ButtonStyle get style => const ButtonStyle();
}
