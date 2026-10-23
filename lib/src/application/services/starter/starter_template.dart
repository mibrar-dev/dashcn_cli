// Simple `{{var}}` substitution for starter templates (P9-6).
//
// Templates use five variables: app name, package name, imports per mode,
// theme preset and theme build function. Nothing else is substituted, so a
// literal `{{` in Dart code would survive unchanged except for these names.

/// Renders [template] by replacing `{{var}}` with [vars]`[var]`.
String renderStarterTemplate(String template, Map<String, String> vars) {
  var out = template;
  for (final entry in vars.entries) {
    out = out.replaceAll('{{${entry.key}}}', entry.value);
  }
  return out;
}

/// `amber-minimal` becomes `amberMinimal` (matches the kit generator).
String starterCamelCase(String id) {
  final parts = id.split(RegExp('[^A-Za-z0-9]')).where((p) => p.isNotEmpty);
  final buffer = StringBuffer();
  for (final part in parts) {
    if (buffer.isEmpty) {
      buffer.write(part.toLowerCase());
    } else {
      buffer.write(part[0].toUpperCase() + part.substring(1));
    }
  }
  return buffer.toString();
}

/// `neutral` becomes `buildNeutralTheme` (matches `gen_app_theme.dart`).
String starterThemeBuild(String preset) {
  final camel = starterCamelCase(preset);
  if (camel.isEmpty) {
    return 'buildTheme';
  }
  return 'build${camel[0].toUpperCase()}${camel.substring(1)}Theme';
}

/// `My App` from `my_app` for the DashcnApp title.
String starterAppName(String packageName) {
  final parts = packageName.split(RegExp('[_\\-]+')).where((p) => p.isNotEmpty);
  return parts
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join(' ');
}

/// Validates a `flutter create` project name (lowercase, underscores).
bool isValidPackageName(String name) {
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name);
}

/// Sanitizes a directory name into a package name.
String sanitizePackageName(String name) {
  var out = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  if (out.isEmpty) {
    return 'my_app';
  }
  if (!RegExp(r'^[a-z]').hasMatch(out)) {
    out = 'app_$out';
  }
  return out;
}

/// Import block for one generated file, per starter, target and mode.
///
/// Every branch lists only the symbols that file uses: unused imports would
/// fail `flutter analyze` in the generated app.
String starterImports({
  required String starterId,
  required String target,
  required String mode,
}) {
  final package = mode == 'package';
  if (target.endsWith('lib/app.dart')) {
    if (package) {
      final flows = _appFlowsPackage(starterId);
      return <String>[
        "import 'package:flutter/widgets.dart';",
        "import 'package:dashcn/dashcn.dart';",
        for (final flow in flows) "import 'package:dashcn/flows/$flow.dart';",
        "import 'app_theme.dart';",
      ].join('\n');
    }
    final flows = _appFlowsCopy(starterId);
    return <String>[
      "import 'package:flutter/widgets.dart';",
      "import 'ui/dashcn/components/app/app.dart';",
      for (final flow in flows) "import '$flow';",
      "import 'ui/dashcn/theme/app_theme.dart';",
    ].join('\n');
  }
  if (target.endsWith('lib/shell.dart')) {
    if (package) {
      return <String>[
        "import 'package:flutter/widgets.dart';",
        "import 'package:dashcn/dashcn.dart';",
        for (final line in _shellFlowsBlocksPackage(starterId)) line,
      ].join('\n');
    }
    return <String>[
      "import 'package:flutter/widgets.dart';",
      "import 'ui/dashcn/components/navigation_bar/navigation_bar.dart';",
      "import 'ui/dashcn/foundation/icons/radix_icons.dart';",
      "import 'ui/dashcn/primitives/localizations/localizations.dart';",
      for (final line in _shellFlowsBlocksCopy(starterId)) line,
    ].join('\n');
  }
  if (target.endsWith('lib/shop/product_grid.dart')) {
    if (package) {
      return <String>[
        "import 'package:flutter/widgets.dart';",
        "import 'package:dashcn/dashcn.dart';",
      ].join('\n');
    }
    return <String>[
      "import 'package:flutter/widgets.dart';",
      "import '../ui/dashcn/components/card/card.dart';",
      "import '../ui/dashcn/components/badge/badge.dart';",
      "import '../ui/dashcn/components/button/button.dart';",
      "import '../ui/dashcn/components/image/image.dart';",
      "import '../ui/dashcn/primitives/localizations/localizations.dart';",
    ].join('\n');
  }
  return "import 'package:flutter/widgets.dart';";
}

List<String> _appFlowsPackage(String starterId) {
  switch (starterId) {
    case 'saas':
      return <String>['auth_01', 'onboarding_01'];
    case 'chat':
    case 'shop':
      return <String>['auth_01'];
    default:
      return <String>['auth_01'];
  }
}

List<String> _appFlowsCopy(String starterId) {
  switch (starterId) {
    case 'saas':
      return <String>[
        'ui/dashcn/flows/auth-01/flow.dart',
        'ui/dashcn/flows/onboarding-01/flow.dart',
      ];
    case 'chat':
    case 'shop':
      return <String>['ui/dashcn/flows/auth-01/flow.dart'];
    default:
      return <String>['ui/dashcn/flows/auth-01/flow.dart'];
  }
}

List<String> _shellFlowsBlocksPackage(String starterId) {
  switch (starterId) {
    case 'saas':
      return <String>[
        "import 'package:dashcn/blocks/dashboard_01.dart';",
        "import 'package:dashcn/blocks/pricing_01.dart';",
        "import 'package:dashcn/flows/settings_01.dart';",
      ];
    case 'chat':
      return <String>[
        "import 'package:dashcn/flows/chat_01.dart';",
        "import 'package:dashcn/flows/settings_01.dart';",
      ];
    case 'shop':
      return <String>[
        "import 'package:dashcn/flows/checkout_01.dart';",
        "import 'package:dashcn/flows/settings_01.dart';",
      ];
    default:
      return const <String>[];
  }
}

List<String> _shellFlowsBlocksCopy(String starterId) {
  switch (starterId) {
    case 'saas':
      return <String>[
        "import 'ui/dashcn/blocks/dashboard-01/dashboard_01.dart';",
        "import 'ui/dashcn/blocks/pricing-01/pricing_01.dart';",
        "import 'ui/dashcn/flows/settings-01/flow.dart';",
      ];
    case 'chat':
      return <String>[
        "import 'ui/dashcn/flows/chat-01/flow.dart';",
        "import 'ui/dashcn/flows/settings-01/flow.dart';",
      ];
    case 'shop':
      return <String>[
        "import 'ui/dashcn/flows/checkout-01/flow.dart';",
        "import 'ui/dashcn/flows/settings-01/flow.dart';",
      ];
    default:
      return const <String>[];
  }
}
