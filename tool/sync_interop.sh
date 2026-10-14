#!/usr/bin/env bash
# Vendors the kit's pure-Dart web-theme interop layer into this repo.
#
# The kit owns `dashcn/lib/src/theme/interop/` (P9-4a, no `package:` imports,
# only `dart:` + relative ones), so the directory copies as-is to
# `lib/src/theme_interop/`. Never edit the vendored copy by hand: fix the kit
# and re-run this script.
#
# Usage:
#   tool/sync_interop.sh           # copy kit -> lib/src/theme_interop/
#   tool/sync_interop.sh --check   # fail when the vendored copy drifted
#
# The formatter's style depends on the package language version (kit: 3.12,
# CLI: 3.3), so the copy is formatted with the CLI's version right after it is
# vendored, and --check compares against a freshly vendored + formatted copy.
# A repo-wide `dart format .` therefore stays clean.
#
# DASHCN_KIT_ROOT may point at the kit repo root (as the e2e tests use) or at
# its `dashcn/` package directory.
set -euo pipefail

lang_version="3.3"   # keep in sync with the lower bound of `sdk:` in pubspec.yaml

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cli_root="$(cd "$here/.." && pwd)"
dest="$cli_root/lib/src/theme_interop"

kit_root="${DASHCN_KIT_ROOT:-}"
if [[ -n "$kit_root" && -d "$kit_root/dashcn/lib/src/theme/interop" ]]; then
  kit_root="$kit_root/dashcn"
fi
if [[ -z "$kit_root" ]]; then
  kit_root="$(cd "$cli_root/../dashcn-kit/dashcn" 2>/dev/null && pwd || true)"
fi
src="${kit_root:-}/lib/src/theme/interop"

if [[ "${1:-}" == "--check" ]]; then
  if [[ -z "$kit_root" || ! -d "$src" ]]; then
    echo "sync_interop --check: kit not found (set DASHCN_KIT_ROOT); skipping" >&2
    exit 0
  fi
  if [[ ! -d "$dest" ]]; then
    echo "sync_interop --check: $dest missing; run tool/sync_interop.sh" >&2
    exit 1
  fi
  expected="$(mktemp -d)"
  trap 'rm -rf "$expected"' EXIT
  cp -r "$src/." "$expected/"
  dart format --language-version="$lang_version" "$expected" > /dev/null
  if diff -r -q "$expected" "$dest" > /dev/null; then
    echo "sync_interop: vendored interop is up to date"
  else
    echo "sync_interop --check: vendored copy drifted from $src" >&2
    diff -r "$expected" "$dest" | head -20 >&2 || true
    echo "run tool/sync_interop.sh to re-vendor" >&2
    exit 1
  fi
  exit 0
fi

if [[ -z "$kit_root" || ! -d "$src" ]]; then
  echo "error: kit interop not found at ${src:-<unset>} (set DASHCN_KIT_ROOT)" >&2
  exit 1
fi
rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/." "$dest/"
dart format --language-version="$lang_version" "$dest" > /dev/null
echo "sync_interop: vendored $src -> $dest"
