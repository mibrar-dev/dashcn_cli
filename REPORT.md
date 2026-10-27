# E2E Report: `dashcn fonts add` / `list` (Task B)

Scratch app: `fonts_e2e_app` (`flutter create --empty`) under
`scratchpad/fonts-plan/e2e/`. Local registry: `e2e/registry/` (hand-built,
contract-shaped `fonts` map with `geist-sans` and `noto-symbols`; the kit's
real registry has no `fonts` map yet — task A must merge first). CLI run from
source: `dart bin/dashcn.dart --registry <local-registry> ...`.

`flutter analyze` in the scratch app after `fonts add geist-sans` + `add
button`: 1 pre-existing-style warning only (`unused_import` in the hand-made
fixture's `button.dart`), no errors. Copied font bytes are identical (`cmp`).
`add button` added no font file and no pubspec `fonts:` entry of its own.

## Transcript

```
$ dashcn fonts list --registry <local-registry>
id           families             installed
geist-sans   GeistSans            no
noto-symbols NotoSansSymbols2     no

Apps use the platform font by default; add a pack with `dashcn fonts add <id>`.
exit=0

$ dashcn fonts add geist-sans --registry <local-registry>
✓ Installed font geist-sans (GeistSans).
  assets/fonts/Geist-Bold.otf
  assets/fonts/Geist-Regular.otf
  assets/fonts/state.json
  pubspec.yaml
exit=0

$ dashcn fonts add geist-sans (again: idempotence)
✓ Font geist-sans is already installed (GeistSans).
exit=0

$ dashcn add button (must install no font)
✨ Installed 1 component(s)
  files written: 4
exit=0

--- project assets/fonts ---
total 24
-rw-r--r--@ 1 ibrar  wheel   27 Oct 27 05:53 Geist-Bold.otf
-rw-r--r--@ 1 ibrar  wheel   30 Oct 27 05:53 Geist-Regular.otf
-rw-r--r--@ 1 ibrar  wheel   38 Oct 27 05:53 state.json
--- pubspec flutter section ---
flutter:
  uses-material-design: true

  fonts:
    - family: GeistSans
      fonts:
        - asset: assets/fonts/Geist-Bold.otf
          weight: 700
        - asset: assets/fonts/Geist-Regular.otf
          weight: 400
--- state.json ---
{
  "fonts": [
    "geist-sans"
  ]
}
--- byte-identical check ---
Geist-Regular.otf identical
Geist-Bold.otf identical

$ flutter analyze
Analyzing fonts_e2e_app...
warning • Unused import: '../../foundation/data.dart'. Try removing the import directive • lib/ui/dashcn/components/button/button.dart:1:8 • unused_import
1 issue found. (ran in 3.4s)
```
