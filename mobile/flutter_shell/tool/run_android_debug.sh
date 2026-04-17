#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if [ -z "${JAVA_HOME:-}" ] && [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

if [ -n "${JAVA_HOME:-}" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

if ! command -v adb >/dev/null 2>&1 && [ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
  export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1 && [ -x "/tmp/flutter-sdk/bin/flutter" ]; then
  export PATH="/tmp/flutter-sdk/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH." >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is not on PATH." >&2
  exit 1
fi

probe_port() {
  port="$1"

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  curl --silent --fail --max-time 2 "http://127.0.0.1:$port/" >/dev/null
}

if [ -n "${INKCREATE_DEBUG_BASE_URL:-}" ]; then
  debug_base_url="$INKCREATE_DEBUG_BASE_URL"
else
  debug_port="${INKCREATE_DEBUG_PORT:-}"

  if [ -z "$debug_port" ]; then
    for candidate_port in 8080 3000; do
      if probe_port "$candidate_port"; then
        debug_port="$candidate_port"
        break
      fi
    done
  fi

  if [ -n "$debug_port" ]; then
    debug_base_url="http://127.0.0.1:$debug_port"
  else
    debug_base_url="http://127.0.0.1:3000"
  fi
fi

reverse_port=""

case "$debug_base_url" in
  http://127.0.0.1:*|http://localhost:*)
    reverse_port="$(printf '%s\n' "$debug_base_url" | sed -E 's#^http://(127\.0\.0\.1|localhost):([0-9]+).*$#\2#')"
    if [ -z "$reverse_port" ]; then
      echo "Could not parse a local debug port from $debug_base_url." >&2
      exit 1
    fi

    if ! probe_port "$reverse_port"; then
      echo "Nothing is listening on $debug_base_url." >&2
      echo "Start the InkCreate Rails app first, or set INKCREATE_DEBUG_BASE_URL to a reachable host." >&2
      exit 1
    fi
    ;;
esac

export INKCREATE_DEBUG_BASE_URL="$debug_base_url"

device_id="${INKCREATE_ANDROID_DEVICE_ID:-}"

if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  device_id="$1"
  shift
fi

if [ -z "$device_id" ]; then
  devices="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')"

  if [ -z "$devices" ]; then
    echo "No Android devices are connected." >&2
    exit 1
  fi

  device_count="$(printf '%s\n' "$devices" | awk 'NF { count++ } END { print count + 0 }')"

  if [ "$device_count" -gt 1 ]; then
    echo "Multiple Android devices are connected. Pass a device id." >&2
    printf '  %s\n' $devices >&2
    exit 1
  fi

  device_id="$(printf '%s\n' "$devices" | awk 'NF { print; exit }')"
fi

if [ -n "$reverse_port" ]; then
  adb -s "$device_id" reverse "tcp:$reverse_port" "tcp:$reverse_port" >/dev/null
  echo "ADB reverse enabled for $device_id: device tcp:$reverse_port -> host tcp:$reverse_port"
fi

cd "$PROJECT_DIR"
exec flutter run -d "$device_id" --dart-define="INKCREATE_DEBUG_BASE_URL=$debug_base_url" "$@"
