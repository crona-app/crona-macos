#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${CRONA_DERIVED_DATA:-/private/tmp/crona-macos-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
cd "$ROOT_DIR"
# Match the executable path, never the process name: release and installed apps
# also run as "crona" and must remain untouched.
while read -r process_id executable; do
  case "$executable" in
    /*/Build/Products/Debug/crona.app/Contents/MacOS/crona)
      kill "$process_id" 2>/dev/null || true
      ;;
  esac
done < <(/bin/ps -axo pid=,comm=)
xcodebuild -project crona.xcodeproj -scheme crona -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/crona.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/crona"
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "crona"'
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.crona.macos"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    /bin/ps -axo comm= | /usr/bin/grep -Fx -- "$APP_BINARY" >/dev/null
    ;;
esac
