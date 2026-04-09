#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source .env 2>/dev/null || true
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-ChangeMeN0w!}"
SPLUNK_URL="https://localhost:8089"
SPLUNK_AUTH="admin:${SPLUNK_PASSWORD}"
OUTPUT_DIR="exported_rules"

mkdir -p "$OUTPUT_DIR"

echo "========================================="
echo " Exporting Detection Rules from Splunk"
echo "========================================="

# Detection rule names to export (savedsearch names from ESCU)
declare -a RULES=(
  "ESCU - Linux APT Privilege Escalation - Rule"
  "ESCU - Malicious PowerShell Process - Encoded Command - Rule"
  "ESCU - Registry Keys Used For Persistence - Rule"
  "ESCU - Deleting Shadow Copies - Rule"
  "ESCU - Windows Event Log Cleared - Rule"
  "ESCU - Windows Eventlog Cleared Via Wevtutil - Rule"
  "ESCU - Windows Scheduled Task with Suspicious Command - Rule"
  "ESCU - Windows OS Credential Dumping with Procdump - Rule"
  "ESCU - Attacker Tools On Endpoint - Rule"
  "ESCU - AWS Defense Evasion Delete Cloudtrail - Rule"
  "ESCU - AWS IAM AccessDenied Discovery Events - Rule"
  "ESCU - AWS CreateAccessKey - Rule"
)

echo ""
echo "Listing all available ESCU saved searches..."
# First, list what's actually available so we can match names
curl -ks -u "$SPLUNK_AUTH" \
  "${SPLUNK_URL}/servicesNS/-/-/saved/searches" \
  -d "output_mode=json" \
  -d "count=0" \
  -d "search=ESCU" 2>/dev/null \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
entries = data.get('entry', [])
print(f'Found {len(entries)} ESCU saved searches')
for e in entries[:20]:
    print(f'  - {e[\"name\"]}')
if len(entries) > 20:
    print(f'  ... and {len(entries)-20} more')
" 2>/dev/null || echo "Could not list saved searches. Splunk may not be ready."

echo ""
echo "Exporting individual rules..."

for rule_name in "${RULES[@]}"; do
  safe_name=$(echo "$rule_name" | sed 's/[^a-zA-Z0-9_-]/_/g')
  echo "  Exporting: ${rule_name}"

  curl -ks -u "$SPLUNK_AUTH" \
    "${SPLUNK_URL}/servicesNS/-/-/saved/searches/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${rule_name}', safe=''))")" \
    -d "output_mode=json" 2>/dev/null \
    > "${OUTPUT_DIR}/${safe_name}.json" || echo "    FAILED"
done

echo ""
echo "Exporting all macros (for reference)..."
curl -ks -u "$SPLUNK_AUTH" \
  "${SPLUNK_URL}/servicesNS/-/-/admin/macros" \
  -d "output_mode=json" \
  -d "count=0" 2>/dev/null \
  > "${OUTPUT_DIR}/all_macros.json" || echo "  FAILED"

echo ""
echo "Exporting all lookups (for reference)..."
curl -ks -u "$SPLUNK_AUTH" \
  "${SPLUNK_URL}/servicesNS/-/-/data/transforms/lookups" \
  -d "output_mode=json" \
  -d "count=0" 2>/dev/null \
  > "${OUTPUT_DIR}/all_lookups.json" || echo "  FAILED"

echo ""
echo "========================================="
echo " Export Complete"
echo " Files saved to: ${OUTPUT_DIR}/"
echo "========================================="
ls -la "$OUTPUT_DIR/"
