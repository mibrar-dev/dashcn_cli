# REPORT: wire component translations into the `dashcn` CLI

Branch: `feat/locale-install` (repo `mibrar-dev/dashcn_cli`).
Kit side: `mibrar-dev/dashcn` PR #66, branch `feat/cli-install-translations`
(local checkout `dashcn-w-clii18n`).

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

Temp Flutter app, CLI run from source (`dart run bin/dashcn.dart`) against
the local kit checkout (`--registry …/dashcn-w-clii18n/dashcn/lib/src`):

- `init --mode copy --yes` → theme applied, `archive` package added
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
- Slim check: `lib/ui/dashcn/primitives/localizations/` holds only the
  neutral files + the generated English-fallback delegate — no per-locale
  tables (`localizations_ar.dart` etc. absent)
- Generated `dashcn_locale_en/ar.dart` override exactly the needed keys
  with real translations; the barrel exposes `dashcnLocalesDelegates` /
  `dashcnSupportedLocales` with `package:<app>/…` imports
- `doctor` → components: 3, files: 102 (0 modified, 0 missing), clean
- `flutter analyze` on the temp app → `No issues found!`

## Full E2E transcript (pasted)

```
+zsh:1> cd /var/folders/dt/p77q2g1j7190pw1cc_h07hg80000gn/T//dashcn_locale_e2e
+zsh:1> dart run /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn_cli-w-locale/bin/dashcn.dart --registry /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn-w-clii18n/dashcn/lib/src init --mode copy --yes
✓ Added packages: archive
✓ Applied theme Neutral (lib/ui/dashcn/theme/app_theme.dart)
✨ Initialized dashcn
  install root: lib/ui/dashcn
  theme:        Neutral (lib/ui/dashcn/theme/app_theme.dart)
  packages:     archive

Next: dashcn add button
+zsh:1> echo '=== ADD BUTTON ==='
=== ADD BUTTON ===
+zsh:1> dart run /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn_cli-w-locale/bin/dashcn.dart --registry /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn-w-clii18n/dashcn/lib/src add button
✓ Added packages: flutter_localizations, intl
✓ Locales refreshed (3 keys for en).
✨ Installed 2 component(s)
  files written: 47
  packages added: flutter_localizations, intl
+zsh:1> echo '=== LOCALES AFTER BUTTON ==='
=== LOCALES AFTER BUTTON ===
+zsh:1> ls dashcn_locales/
dashcn_locale_en.dart
dashcn_locales.dart
state.json
+zsh:1> echo '=== LOCALE ADD AR ==='
=== LOCALE ADD AR ===
+zsh:1> dart run /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn_cli-w-locale/bin/dashcn.dart --registry /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn-w-clii18n/dashcn/lib/src locale add ar
✓ Installed locale ar (3 keys for ar, en).
  dashcn_locales/dashcn_locale_ar.dart
  dashcn_locales/dashcn_locales.dart
  dashcn_locales/state.json
+zsh:1> echo '=== ADD DIALOG ==='
=== ADD DIALOG ===
+zsh:1> dart run /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn_cli-w-locale/bin/dashcn.dart --registry /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn-w-clii18n/dashcn/lib/src add dialog
✓ Locales refreshed (4 keys for ar, en).
✨ Installed 1 component(s)
  files written: 4
+zsh:1> echo '=== IDEMPOTENCE: locale add ar again ==='
=== IDEMPOTENCE: locale add ar again ===
+zsh:1> dart run /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn_cli-w-locale/bin/dashcn.dart --registry /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn-w-clii18n/dashcn/lib/src locale add ar
✓ Locale ar is already installed (4 keys for ar, en).
+zsh:1> echo '=== LOCALE LIST ==='
=== LOCALE LIST ===
+zsh:1> dart run /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn_cli-w-locale/bin/dashcn.dart --registry /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/dashcn-w-clii18n/dashcn/lib/src locale list
code     direction installed keys
en       ltr       yes       491
ar       rtl       yes       491
de       ltr       no        491
es       ltr       no        491
fa       rtl       no        491
fr       ltr       no        491
he       rtl       no        491
hi       ltr       no        491
it       ltr       no        491
ja       ltr       no        491
ko       ltr       no        491
nl       ltr       no        491
pt       ltr       no        491
pt-BR    ltr       no        6
ru       ltr       no        491
tr       ltr       no        491
ur       rtl       no        491
zh       ltr       no        491
zh-Hans  ltr       no        1

English (en) is always installed; other locales are added with `dashcn locale add <code>`.
+zsh:1> echo '=== STATE ==='
=== STATE ===
+zsh:1> cat dashcn_locales/state.json
{
  "components": [
    "button",
    "dialog",
    "spinner"
  ],
  "locales": [
    "ar",
    "en"
  ]
}
+zsh:1> echo '=== SLIM CHECK: per-locale tables copied (expect none) ==='
=== SLIM CHECK: per-locale tables copied (expect none) ===
+zsh:1> ls lib/ui/dashcn/primitives/localizations/
+zsh:1> grep -E 'localizations_[a-z]+\.dart'
localizations_blocks.dart
localizations_chrome.dart
localizations_dashcn.dart
localizations_delegate.dart
localizations_error.dart
localizations_extensions.dart
localizations_files.dart
localizations_form.dart
localizations_media.dart
localizations_misc.dart
localizations_overlay.dart
+zsh:1> echo '=== EN FILE IMPORT ==='
=== EN FILE IMPORT ===
+zsh:1> grep -n import dashcn_locales/dashcn_locale_en.dart
4:import 'package:flutter/widgets.dart';
6:import 'package:dashcn_locale_e2e/ui/dashcn/primitives/localizations/localizations.dart';
+zsh:1> echo '=== FLUTTER ANALYZE ==='
=== FLUTTER ANALYZE ===
+zsh:1> flutter analyze
Analyzing dashcn_locale_e2e...
No issues found! (ran in 2.7s)
```

(Raw log also kept at `qa_reports/locale-install-e2e-transcript.txt`;
the slim-check listing shows the neutral files plus the generated
`localizations_delegate.dart` English-fallback — no `localizations_ar.dart`
style per-locale tables.)

## Verification (CLI repo, re-run 2026-10-23)

- `dart analyze`: `No issues found!`
- `dart format --set-exit-if-changed` on all touched files: clean (0 changed)
- `dart test test/locale_sync_test.dart`: 20/20 passed
- `dart test` (full suite): 586 passed, 16 skipped, 0 failed
