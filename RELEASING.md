# Releasing dashcn_cli

The release policy, pub.dev setup and release order are documented once in
the kit repo (`RELEASING.md` at the kit repo root).

CLI specifics:

- The package publishes from the repo root (`pubspec.yaml` →
  `dashcn_cli`, executable `dashcn`), so `publish.yml` passes no
  `working-directory`.
- Tags are `v<cli version>` (same `v{{version}}` pattern as the kit, but the
  two repos tag independently).
- Release the kit first: the default registry pins
  `mibrar-dev/shadcn_flutter_kit@v<cli version>/dashcn/lib/src`, so tag the
  kit `v1.0.0` (with the `dashcn/` layout) before tagging the CLI —
  otherwise a default install resolves against a missing tag.
- Before tagging: CHANGELOG date, `dart format`, `dart analyze`, `dart test`,
  `dart test -t e2e --run-skipped` with `DASHCN_KIT_ROOT` set,
  `dart run tool/rename_cli.dart --check`, `bash tool/sync_interop.sh --check`,
  `dart pub publish --dry-run` (CI runs all of these).
