/// Public metadata helpers exported by `dashcn_cli`.
///
/// Most users interact with this package through the `dashcn` executable
/// after global activation:
///
/// ```bash
/// dart pub global activate dashcn_cli
/// dashcn init --yes
/// dashcn add button
/// ```
///
/// The library API intentionally stays small. It exposes bundled registry
/// theme preset metadata for tooling that wants to inspect preset ids, names,
/// and token maps without shelling out to the CLI.
library;

export 'registry/shared/theme/preset_theme_data.dart';
