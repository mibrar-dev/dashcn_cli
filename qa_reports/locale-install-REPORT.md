# REPORT: wire component translations into the `dashcn` CLI

Branch: `feat/locale-install` (repo `mibrar-dev/dashcn_cli`).
Kit side: `mibrar-dev/dashcn` PR #66, branch `feat/cli-install-translations`.

User requirement: "when installing using the CLI the translations will be
installed as well." Class/parameter names stay English; only UI strings are
translated.

## What changed

1. **Registry schema/validation** (`lib/src/registry/manifest/`): components
   accept the optional `localizationKeys` list (sorted, unique, non-empty
   strings; transitive over deps — the kit generator guarantees the shape).
   Missing list = no keys, so older registries validate unchanged.
   `RegistryManifest.hasLocalizationKeys` marks locale-aware registries; every
   locale path treats false as "locale support off". The kit's `preview`
   block (`{placement: ...}`), shipped on every component of the current kit
   registry, is accepted (validated, never read by the CLI).
2. **`dashcn add` installs translations** (copy mode only): after copying
   files it refreshes `dashcn_locales/` for every locale the project already
   has (English base always), containing only the keys the installed
   components need. Port of the kit's `dashcn/tool/locale.dart` generators,
   adapted to copy mode (`package:<app>/...` import of the installed
   `localizations.dart`, derived from the app's `pubspec.yaml` with a
   relative-path fallback). Reads `manifests/locale_tables.json` through the
   registry source the CLI already uses, so it works offline.
3. **New `dashcn locale add <code>` / `list` / `remove <code>`**: installs a
   language for every installed component (later `add`s include it
   automatically). Idempotent: a rerun writes nothing (content-compared
   writes). `remove` deletes the locale file and refreshes the barrel; the
   English base cannot be removed while components are installed.
4. **Slim copy**: locale-aware installs no longer copy the 40+ per-locale
   tables or the kit's `localizations_delegate.dart` (it imports all of
   them). Only the neutral `localizations*.dart` files are copied, plus a
   generated English-fallback delegate that keeps the installed tree
   self-consistent. Older registries keep the historical full copy.
5. **Wired into every copy-mode mutation**: `add`, `remove` (shrinks keys to
   the remaining components), `sync`, `update` (registry upgrades can add
   keys), `eject`, and `project refresh`. Package mode skips it (the pub
   package ships its own tables); `--dry-run` writes nothing.
6. **Docs**: `dashcn locale --help`, generated reference
   (`doc/reference/commands/project/locale.md` + index),
   `doc/user/commands.md` (`locale` section + `add` note), `README.md`
   workflows section, `CHANGELOG.md` (`[Unreleased]`).
7. **Tests**: `test/locale_sync_test.dart` (20 tests: schema accept/reject,
   model parsing, slim filter, refresh writes + idempotence, key subsetting,
   `package:` import, add-then-locale vs locale-then-add convergence,
   add/remove/list, legacy-registry no-op + clear error) plus parser/matrix
   updates for the reintroduced `locale` command.

## E2E proof

Temp Flutter app (`flutter create --empty locale_proof`, Flutter 3.47.7),
CLI run from source (`dart bin/dashcn.dart`) against the local kit checkout
(`dashcn-w-clii18n`, branch `feat/cli-install-translations`,
`--registry …/dashcn/lib/src`):

- `init --mode copy --yes` → theme applied, `archive` package added
- `add button` → "Locales refreshed (3 keys for en)", 47 files, packages
  `flutter_localizations, intl`
- `dashcn_locales/` after button: `dashcn_locale_en.dart`,
  `dashcn_locales.dart`, `state.json`
- `locale add ar` → "Installed locale ar (3 keys for ar, en)"
- `add dialog` → "Locales refreshed (4 keys for ar, en)" — dialog's extra
  key (`dialogDismiss`) appears in both locales automatically
- `locale add ar` again → "already installed", writes nothing
- `add dialog` again → "files written: 0", user-owned file kept
- `locale list` → 18 shipped locales, en+ar installed, directions correct
- `state.json` records components `[button, dialog, spinner]`
  (spinner = transitive dep) and locales `[ar, en]`
- Slim check: `lib/ui/dashcn/primitives/localizations/` holds only the 13
  neutral files + the generated English-fallback delegate — no per-locale
  tables (`localizations_ar.dart` etc. absent)
- Generated `dashcn_locale_en/ar.dart` override exactly the 4 needed keys
  with real translations (`'فشل'`, `'جارٍ التحميل'`, …); the barrel exposes
  `dashcnLocalesDelegates` / `dashcnSupportedLocales` with
  `package:<app>/…` imports (no relative-into-`lib` imports, no
  `package:dashcn` reference)
- `doctor` → components: 3, files: 102 (0 modified, 0 missing), clean

Full transcript: `qa_reports/locale-install-e2e-transcript.txt` (earlier run
in `dashcn_locale_e2e`; this run in `locale_proof` reproduced it verbatim:
same file sets, same key counts, same messages).

### `flutter analyze` on the temp app

```
Analyzing locale_proof...
No issues found! (ran in 1.0s)
```

Generated files use `package:` imports (app name read from `pubspec.yaml`,
relative-path fallback when there is none), so the temp app analyzes clean —
no `avoid_relative_lib_imports` infos.

## Verification (CLI repo)

- `dart analyze`: `No issues found!`
- `dart format --set-exit-if-changed` on all touched files: clean
- `dart test test/locale_sync_test.dart`: 20/20 passed
- `dart test` (full suite): 586 passed, 16 skipped, 0 failed
