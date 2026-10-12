#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run a disposable end-to-end CLI smoke test against a real Flutter dashcn registry.

Usage:
  tool/cli_manual_smoke.sh --registry-root /absolute/path/to/dashcn/lib/src

Options:
  --registry-root PATH   Local registry root that contains manifests/, foundation/,
                         theme/, primitives/ and components/. Can also be provided
                         as REAL_REGISTRY_ROOT.
  --components LIST      Space-separated component ids to install.
                         Default: "button dialog input select calendar".
  --strict-analyze       Treat flutter analyze issues as a smoke failure.
  --keep                 Keep the temporary Flutter app after the run.
  --help                 Show this help.
USAGE
}

CLI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REGISTRY_ROOT="${REAL_REGISTRY_ROOT:-}"
COMPONENTS="button dialog input select calendar"
STRICT_ANALYZE=0
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry-root)
      REGISTRY_ROOT="${2:-}"
      shift 2
      ;;
    --components)
      COMPONENTS="${2:-}"
      shift 2
      ;;
    --strict-analyze)
      STRICT_ANALYZE=1
      shift
      ;;
    --keep)
      KEEP=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$REGISTRY_ROOT" ]]; then
  candidate="$(cd "$CLI_ROOT/.." 2>/dev/null && pwd -P)/dashcn-kit/dashcn/lib/src"
  if [[ -d "$candidate" ]]; then
    REGISTRY_ROOT="$candidate"
  fi
fi

if [[ -z "$REGISTRY_ROOT" || ! -d "$REGISTRY_ROOT" ]]; then
  echo "Registry root not found. Pass --registry-root or set REAL_REGISTRY_ROOT." >&2
  exit 64
fi

for required in manifests foundation theme primitives components; do
  if [[ ! -d "$REGISTRY_ROOT/$required" ]]; then
    echo "Registry root is missing required folder: $REGISTRY_ROOT/$required" >&2
    exit 66
  fi
done

command -v flutter >/dev/null || {
  echo "flutter is required for this smoke test." >&2
  exit 69
}

WORK_ROOT="$(mktemp -d /tmp/dashcn_manual_smoke.XXXXXX)"
APP_ROOT="$WORK_ROOT/app"
LOG_ROOT="$WORK_ROOT/logs"
mkdir -p "$LOG_ROOT"

cleanup() {
  if [[ "$KEEP" -eq 0 ]]; then
    rm -rf "$WORK_ROOT"
  else
    echo "Kept smoke workspace: $WORK_ROOT"
  fi
}
trap cleanup EXIT

run() {
  echo "==> $*"
  "$@"
}

DASHCN=(dart "$CLI_ROOT/bin/dashcn.dart" --registry "$REGISTRY_ROOT")

echo "CLI root: $CLI_ROOT"
echo "Registry root: $REGISTRY_ROOT"
echo "Smoke workspace: $WORK_ROOT"

run flutter create --empty --project-name dashcn_smoke_app "$APP_ROOT" >"$LOG_ROOT/flutter_create.log"
cd "$APP_ROOT"

run "${DASHCN[@]}" version
run "${DASHCN[@]}" init --yes
run "${DASHCN[@]}" list >"$LOG_ROOT/list.txt"
run "${DASHCN[@]}" search button >"$LOG_ROOT/search_button.txt"
run "${DASHCN[@]}" info button >"$LOG_ROOT/info_button.txt"
run "${DASHCN[@]}" dry-run button >"$LOG_ROOT/dry_run_button.txt"

for component in $COMPONENTS; do
  run "${DASHCN[@]}" add "$component"
done

run flutter pub get >"$LOG_ROOT/flutter_pub_get.log"

[[ -f .dashcn/config.json ]] || { echo "Missing .dashcn/config.json" >&2; exit 70; }
[[ -f dashcn.lock ]] || { echo "Missing dashcn.lock" >&2; exit 70; }
[[ -f lib/ui/dashcn/theme/app_theme.dart ]] || {
  echo "Missing generated app_theme.dart." >&2
  exit 70
}
[[ -f lib/ui/dashcn/foundation/data.dart ]] || {
  echo "Missing foundation layer." >&2
  exit 70
}

for component in $COMPONENTS; do
  [[ -f "lib/ui/dashcn/components/$component/$component.dart" ]] || {
    echo "Missing component file: lib/ui/dashcn/components/$component/$component.dart" >&2
    exit 70
  }
done

run "${DASHCN[@]}" doctor
run "${DASHCN[@]}" audit
run "${DASHCN[@]}" update --check

set +e
flutter analyze >"$LOG_ROOT/flutter_analyze.log"
ANALYZE_EXIT=$?
set -e

if [[ "$ANALYZE_EXIT" -ne 0 ]]; then
  echo "flutter analyze reported issues. See: $LOG_ROOT/flutter_analyze.log" >&2
  sed -n '1,80p' "$LOG_ROOT/flutter_analyze.log" >&2
  if [[ "$STRICT_ANALYZE" -eq 1 ]]; then
    exit "$ANALYZE_EXIT"
  fi
fi

echo "Smoke passed init/add/diagnostic checks."
echo "Logs: $LOG_ROOT"
