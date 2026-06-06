#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY_NAME="KEFCompanion"
BASE_BUNDLE_NAME="KEF Companion"
BASE_BUNDLE_IDENTIFIER="com.freddyswift.KEFCompanion"
CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_VARIANT="${KEFCOMPANION_BUILD_VARIANT:-dev}"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"

show_logs=false
verify_launch=false
open_after_build=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      BUILD_VARIANT="dev"
      shift
      ;;
    --prod|--production)
      BUILD_VARIANT="production"
      shift
      ;;
    --logs|--telemetry)
      show_logs=true
      shift
      ;;
    --verify)
      verify_launch=true
      shift
      ;;
    --no-open|--stage-only)
      open_after_build=false
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--dev|--prod] [--verify] [--no-open] [--logs|--telemetry]

Builds and launches a local app bundle. Dev mode is the default and stages
"KEF Companion Dev.app" so local runs are visually distinct from production.

Options:
  --dev        Stage the local bundle as KEF Companion Dev.app (default).
  --prod       Stage the local bundle as KEF Companion.app.
  --verify     Confirm the app process launches.
  --no-open    Build and stage the app bundle without launching it.
  --logs       Stream unified logs after launch.
  --telemetry  Alias for --logs.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

case "$BUILD_VARIANT" in
  dev|development|local)
    BUNDLE_NAME="$BASE_BUNDLE_NAME Dev"
    BUNDLE_IDENTIFIER="$BASE_BUNDLE_IDENTIFIER.dev"
    EXECUTABLE_NAME="KEFCompanionDev"
    ;;
  prod|production|release)
    BUNDLE_NAME="$BASE_BUNDLE_NAME"
    BUNDLE_IDENTIFIER="$BASE_BUNDLE_IDENTIFIER"
    EXECUTABLE_NAME="$BINARY_NAME"
    ;;
  *)
    echo "Unknown KEFCOMPANION_BUILD_VARIANT: $BUILD_VARIANT" >&2
    exit 2
    ;;
esac

default_signing_identity() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null |
    awk -F '"' '/Developer ID Application:/ { print $2; exit }'
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(default_signing_identity)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi

APP_DIR="$ROOT_DIR/dist/$BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$ROOT_DIR"

if [[ "$open_after_build" != true && "$verify_launch" == true ]]; then
  echo "--verify requires launching the app; remove --no-open." >&2
  exit 2
fi

if [[ "$open_after_build" != true && "$show_logs" == true ]]; then
  echo "--logs requires launching the app; remove --no-open." >&2
  exit 2
fi

if [[ "$open_after_build" == true ]] && pgrep -x "$EXECUTABLE_NAME" >/dev/null; then
  killall "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
  sleep 0.2
fi

swift_build() {
  if [[ "$CONFIGURATION" == "release" ]]; then
    swift build -c release "$@"
  else
    swift build "$@"
  fi
}

copy_embedded_frameworks() {
  local bin_dir="$1"
  local frameworks_dir="$CONTENTS_DIR/Frameworks"

  if [[ ! -d "$bin_dir/Sparkle.framework" ]]; then
    echo "Missing Sparkle.framework in $bin_dir." >&2
    exit 2
  fi

  mkdir -p "$frameworks_dir"
  ditto "$bin_dir/Sparkle.framework" "$frameworks_dir/Sparkle.framework"
}

copy_bundle_resources() {
  local resources_dir="$CONTENTS_DIR/Resources"

  mkdir -p "$resources_dir"
  ditto "$ROOT_DIR/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"
  ditto "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$resources_dir/ThirdPartyNotices.txt"
}

codesign_app() {
  local codesign_args=(--force --sign "$SIGNING_IDENTITY" --options runtime --deep)

  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign_args+=(--timestamp)
  fi

  codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null
}

swift_build
BIN_DIR="$(swift_build --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS"
cp "$ROOT_DIR/Sources/KEFCompanion/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/$BINARY_NAME" "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
copy_embedded_frameworks "$BIN_DIR"
copy_bundle_resources

/usr/libexec/PlistBuddy -c "Set :CFBundleName $BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $BUNDLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$CONTENTS_DIR/Info.plist"
if [[ "$BUNDLE_NAME" != "$BASE_BUNDLE_NAME" ]]; then
  /usr/libexec/PlistBuddy -c "Set :NSLocalNetworkUsageDescription $BUNDLE_NAME scans the local network to find and control compatible KEF speakers." "$CONTENTS_DIR/Info.plist"
fi

codesign_app

if [[ "$open_after_build" != true ]]; then
  echo "Staged $APP_DIR"
  exit 0
fi

/usr/bin/open -n "$APP_DIR"

if [[ "$verify_launch" == true ]]; then
  for _ in {1..30}; do
    if pgrep -x "$EXECUTABLE_NAME" >/dev/null; then
      echo "$BUNDLE_NAME launched"
      break
    fi
    sleep 0.2
  done

  if ! pgrep -x "$EXECUTABLE_NAME" >/dev/null; then
    echo "$BUNDLE_NAME did not appear to launch" >&2
    exit 1
  fi
fi

if [[ "$show_logs" == true ]]; then
  /usr/bin/log stream --style compact --info --predicate "process == '$EXECUTABLE_NAME'"
fi
