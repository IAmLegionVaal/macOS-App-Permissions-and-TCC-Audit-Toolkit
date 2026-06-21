#!/bin/bash
set -u

DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
SERVICE=""
BUNDLE_ID=""
RESET_ALL=false
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: tcc_permissions_repair.sh [options]

  --reset SERVICE       Reset one macOS privacy service for one app.
  --reset-all           Reset all resettable privacy decisions for one app.
  --bundle-id ID        Application bundle identifier.
  --dry-run             Show actions without changing privacy decisions.
  --yes                 Skip confirmation prompts.
  --output DIR          Save logs and verification output in DIR.
  -h, --help            Show help.

Examples:
  ./src/tcc_permissions_repair.sh --reset Camera --bundle-id us.zoom.xos
  ./src/tcc_permissions_repair.sh --reset Microphone --bundle-id com.microsoft.teams2
  ./src/tcc_permissions_repair.sh --reset ScreenCapture --bundle-id com.apple.QuickTimePlayerX
  ./src/tcc_permissions_repair.sh --reset-all --bundle-id com.example.app

This tool resets existing decisions so macOS prompts again. It cannot grant permissions automatically.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reset) SERVICE="${2:-}"; shift 2 ;;
    --reset-all) RESET_ALL=true; shift ;;
    --bundle-id) BUNDLE_ID="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }
[ -n "$BUNDLE_ID" ] || { echo "--bundle-id is required." >&2; exit 2; }
if $RESET_ALL && [ -n "$SERVICE" ]; then echo "Choose either --reset SERVICE or --reset-all." >&2; exit 2; fi
if ! $RESET_ALL && [ -z "$SERVICE" ]; then echo "Choose --reset SERVICE or --reset-all." >&2; exit 2; fi

if [ -n "$SERVICE" ]; then
  case "$SERVICE" in
    Camera|Microphone|ScreenCapture|Accessibility|AppleEvents|Location|SystemPolicyAllFiles|SystemPolicyDesktopFolder|SystemPolicyDocumentsFolder|SystemPolicyDownloadsFolder|Photos|Calendar|AddressBook|Reminders|BluetoothAlways) : ;;
    *) echo "Unsupported service name: $SERVICE" >&2; exit 2 ;;
  esac
fi

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "$TARGET_USER" = "root" ]; then
  CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)
  [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || TARGET_USER="$CONSOLE_USER"
fi
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null) || { echo "Target user not found: $TARGET_USER" >&2; exit 2; }
TARGET_HOME=$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./tcc-permission-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_as_target() {
  description="$1"; shift
  if [ "$(id -un)" = "$TARGET_USER" ]; then
    run_action "$description" "$@"
  else
    run_action "$description" /usr/bin/sudo -H -u "$TARGET_USER" "$@"
  fi
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Target user: $TARGET_USER ($TARGET_UID)"
    echo "Bundle ID: $BUNDLE_ID"
    echo "Requested service: ${SERVICE:-All}"
    echo
    echo "TCC database metadata:"
    for db in "$TARGET_HOME/Library/Application Support/com.apple.TCC/TCC.db" "/Library/Application Support/com.apple.TCC/TCC.db"; do
      if [ -e "$db" ]; then /bin/ls -lhO "$db"; else echo "Not found or inaccessible: $db"; fi
    done
    echo
    echo "tccd processes:"
    ps -Ao pid,user,etime,comm,args | grep -E '[t]ccd' || true
    echo
    echo "Recent TCC events:"
    /usr/bin/log show --last 10m --style compact --predicate 'process == "tccd"' 2>/dev/null | tail -n 200 || true
  } > "$VERIFY" 2>&1
}

verify
if $RESET_ALL; then
  prompt="Reset all resettable privacy decisions for $BUNDLE_ID and user $TARGET_USER?"
else
  prompt="Reset $SERVICE permission for $BUNDLE_ID and user $TARGET_USER?"
fi
if ! confirm "$prompt The app must request permission again."; then log "Repair cancelled by user."; exit 0; fi

if $RESET_ALL; then
  run_as_target "Resetting all privacy decisions for $BUNDLE_ID" /usr/bin/tccutil reset All "$BUNDLE_ID" || true
else
  run_as_target "Resetting $SERVICE permission for $BUNDLE_ID" /usr/bin/tccutil reset "$SERVICE" "$BUNDLE_ID" || true
fi

if pgrep -u "$TARGET_UID" -x tccd >/dev/null 2>&1; then
  if [ "$(id -u)" -eq "$TARGET_UID" ]; then
    run_action "Refreshing the user TCC service" /usr/bin/killall tccd || true
  else
    run_action "Refreshing the user TCC service" /usr/bin/sudo /usr/bin/killall -u "$TARGET_USER" tccd || true
  fi
fi

if ! $DRY_RUN; then sleep 4; fi
verify

if [ "$FAILURES" -gt 0 ]; then log "Permission reset completed with $FAILURES warning(s)."; exit 1; fi
log "Permission reset completed successfully. Actions performed: $ACTIONS"
exit 0
