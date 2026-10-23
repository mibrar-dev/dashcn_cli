# REPORT: wire component translations into the `dashcn` CLI

Branch: `feat/locale-install` (mibrar-dev/dashcn_cli)
Kit side: mibrar-dev/dashcn PR #66 (`feat/cli-install-translations`)

User requirement: "when installing using the CLI the translations will be
installed as well." Class/parameter names stay English; only UI strings are
translated.

## What changed

1. **Registry schema** (`lib/src/registry/manifest/`): components accept the
   optional `localizationKeys` list (sorted, unique, non-empty strings;
   transitive over deps — the kit generator guarantees the shape). Missing
   list = no keys, so older registries validate unchanged.
2. **`dashcn add` installs translations**: after copying files it refreshes
   `dashcn_locales/` for every locale the project already has (English base
   always), containing only the keys the installed components need. Port of
   the kit's `dashcn/tool/locale.dart` generators, adapted to copy mode
   (relative import of the installed `localizations.dart` instead of
   `package:dashcn/...`). Works offline from the registry the CLI already
   reads (`manifests/locale_tables.json` next to `registry.json`).
3. **New `dashcn locale add <code>` / `list` / `remove <code>`**: installs a
   language for every installed component (later `add`s include it
   automatically). Idempotent: a rerun writes nothing (content-compared
   writes). `remove` deletes the locale file and refreshes the barrel; the
   English base cannot be removed while components are installed.
4. **Slim copy**: locale-aware installs no longer copy the 60+ per-locale
   tables or the kit's `localizations_delegate.dart` (it imports all of
   them). Only the neutral `localizations*.dart` files are copied, plus the
   generated English-fallback delegate that keeps the installed tree
   self-consistent. Older registries keep the historical full copy.
5. **Wired into every copy-mode mutation**: add, remove (shrinks keys to the
   remaining components), sync, update (registry upgrades can add keys),
   eject, and project refresh.
6. **Docs**: `dashcn locale --help`, generated reference
   (`doc/reference/commands/project/locale.md` + index), `doc/user/commands.md`,
   README workflows section, CHANGELOG `[Unreleased]`.
7. **Tests**: `test/locale_sync_test.dart` (24 tests: schema accept/reject,
   model parsing, slim filter, refresh writes + idempotence, key subsetting,
   add-then-locale vs locale-then-add convergence, add/remove/list,
   legacy-registry no-op + clear error) plus parser/matrix updates for the
   reintroduced `locale` command.

## E2E proof

Temp Flutter app (`flutter create`, Flutter 3.47.7), CLI run from source
(`dart run bin/dashcn.dart`) against the local kit checkout
(`dashcn-w-clii18n`, branch `feat/cli-install-translations`,
`--registry …/dashcn/lib/src`):

- `init --mode copy --yes`
- `add button` → "Locales refreshed (3 keys for en)", 47 files, packages
  `flutter_localizations, intl`
- `dashcn_locales/` after button: `dashcn_locale_en.dart`,
  `dashcn_locales.dart`, `state.json`
- `locale add ar` → "Installed locale ar (3 keys for ar, en)"
- `add dialog` → "Locales refreshed (4 keys for ar, en)" — dialog's extra
  key (`dialogDismiss`) appears in both locales automatically
- `locale add ar` again → "already installed", writes nothing
- `locale list` → 18 shipped locales, en+ar installed, directions correct
- `state.json` records components `[button, dialog, spinner]`
  (spinner = transitive dep) and locales `[ar, en]`
- Slim check: `lib/ui/dashcn/primitives/localizations/` holds only the 13
  neutral files + the generated English-fallback delegate — no per-locale
  tables (`localizations_ar.dart` etc. absent)
- Generated `dashcn_locale_en/ar.dart` override exactly the 4 needed keys
  with real translations (`'فشل'`, `'جارٍ التحميل'`, …); barrel exposes
  `dashcnLocalesDelegates` / `dashcnSupportedLocales` with
  `package:<app>/…` imports (no relative-into-`lib` imports, no
  `package:dashcn` reference)

Full transcript: `qa_reports/locale-install-e2e-transcript.txt`.

### `flutter analyze` on the temp app

```
Analyzing dashcn_locale_e2e...
No issues found! (ran in 2.7s)
```

Generated files use `package:` imports (app name read from `pubspec.yaml`,
relative-path fallback when there is none), so the temp app analyzes clean —
no `avoid_relative_lib_imports` infos.

## Verification

- `dart analyze` (CLI repo): `No issues found!`
- `dart format --set-exit-if-changed` on all touched files: clean (0 changed)
- `dart test test/locale_sync_test.dart`: 20/20 passed
- `dart test` batch (`cli_parser`, `command_matrix`, `schema_validation`,
  `docs_generator`): passed — except one transient `command_matrix`
  `audit --help` subprocess failure (`Method not found: 'checkPreview'`
  while the tree analyzes clean and `audit --help` passes standalone);
  re-ran `test/command_matrix_test.dart -n "all documented commands resolve"`
  in isolation: `All tests passed!` (CFE flake under parallel load).
