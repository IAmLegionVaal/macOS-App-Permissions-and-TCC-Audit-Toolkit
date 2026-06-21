#!/bin/bash
set -u

HOURS=24
OUTPUT_DIR=""

usage() {
  echo "Usage: tcc_permissions_audit.sh [--hours N] [--output DIR]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$HOURS" in ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2 ;; esac
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./tcc-audit-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/tcc-audit.txt"
CSV="$OUTPUT_DIR/permissions.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"
echo 'database,service,client,client_type,authorization,last_modified' > "$CSV"

section() {
  title="$1"
  shift
  { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true
}

safe_csv() {
  printf '%s' "$1" | sed 's/"/""/g'
}

section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
section "TCC process state" /bin/bash -c 'ps -Ao pid,user,etime,comm,args | grep -E "[t]ccd" || true'
section "TCC database metadata" /bin/bash -c 'for db in "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "/Library/Application Support/com.apple.TCC/TCC.db"; do if [ -e "$db" ]; then ls -ldeO@ "$db"; else echo "Missing: $db"; fi; done'
section "Recent privacy events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(process == \"tccd\") OR (subsystem CONTAINS[c] \"TCC\") OR (eventMessage CONTAINS[c] \"privacy\") OR (eventMessage CONTAINS[c] \"screen recording\")' 2>/dev/null | tail -n 4000"

USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYSTEM_DB="/Library/Application Support/com.apple.TCC/TCC.db"
ACCESSIBLE_DATABASES=0
INACCESSIBLE_DATABASES=0
RECORDS=0

query_db() {
  db="$1"
  label="$2"

  if [ ! -f "$db" ]; then
    return 0
  fi

  if ! command -v sqlite3 >/dev/null 2>&1; then
    INACCESSIBLE_DATABASES=$((INACCESSIBLE_DATABASES + 1))
    return 0
  fi

  if ! sqlite3 "$db" 'select count(*) from access;' >/dev/null 2>>"$ERRORS"; then
    INACCESSIBLE_DATABASES=$((INACCESSIBLE_DATABASES + 1))
    return 0
  fi

  ACCESSIBLE_DATABASES=$((ACCESSIBLE_DATABASES + 1))

  sqlite3 -separator $'\t' "$db" "select service,client,client_type,auth_value,last_modified from access where service in ('kTCCServiceCamera','kTCCServiceMicrophone','kTCCServiceScreenCapture','kTCCServiceAccessibility','kTCCServiceAppleEvents','kTCCServiceSystemPolicyAllFiles','kTCCServiceSystemPolicyDesktopFolder','kTCCServiceSystemPolicyDocumentsFolder','kTCCServiceSystemPolicyDownloadsFolder','kTCCServiceLocation') order by service,client;" 2>>"$ERRORS" | while IFS=$'\t' read -r service client client_type auth_value modified; do
    case "$auth_value" in
      0) decision="Denied" ;;
      1) decision="Unknown" ;;
      2) decision="Allowed" ;;
      3) decision="Limited" ;;
      *) decision="Value-$auth_value" ;;
    esac

    printf '"%s","%s","%s","%s","%s","%s"\n' \
      "$label" \
      "$(safe_csv "$service")" \
      "$(safe_csv "$client")" \
      "$client_type" \
      "$decision" \
      "$modified" >> "$CSV"
  done
}

query_db "$USER_DB" "user"
query_db "$SYSTEM_DB" "system"

RECORDS="$(awk 'END {print NR-1}' "$CSV")"
ALLOWED="$(awk -F, 'NR>1 && $5 ~ /Allowed/ {c++} END {print c+0}' "$CSV")"
DENIED="$(awk -F, 'NR>1 && $5 ~ /Denied/ {c++} END {print c+0}' "$CSV")"
TCCD_RUNNING=false
pgrep -x tccd >/dev/null 2>&1 && TCCD_RUNNING=true
OVERALL="Healthy"
if ! $TCCD_RUNNING || [ "$ACCESSIBLE_DATABASES" -eq 0 ]; then OVERALL="Review required"; fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "tccd_running": $TCCD_RUNNING,
  "accessible_databases": $ACCESSIBLE_DATABASES,
  "inaccessible_or_missing_databases": $INACCESSIBLE_DATABASES,
  "permission_records": $RECORDS,
  "allowed_records": $ALLOWED,
  "denied_records": $DENIED,
  "overall_status": "$OVERALL"
}
EOF

printf '\nTCC permission audit completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
