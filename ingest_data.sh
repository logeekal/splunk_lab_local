#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source .env 2>/dev/null || true
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-ChangeMeN0w!}"
HEC_TOKEN="${SPLUNK_HEC_TOKEN:-a1b2c3d4-e5f6-7890-abcd-ef1234567890}"
HEC_URL="https://localhost:8088/services/collector/raw"
SPLUNK_URL="https://localhost:8089"
SPLUNK_AUTH="admin:${SPLUNK_PASSWORD}"
ATTACK_DATA="repos/attack_data"

if [ ! -d "$ATTACK_DATA" ]; then
  echo "ERROR: attack_data repo not found. Run ./setup.sh first."
  exit 1
fi

# Detection rules we want to test, with their datasets and sourcetypes.
# Format: "MITRE_ID/SUBFOLDER/FILENAME|SOURCETYPE|SOURCE|INDEX"
declare -a DATASETS=(
  # ── Windows Endpoint ──
  # Rule: Malicious PowerShell - Encoded Command (T1027)
  "attack_techniques/T1027/atomic_red_team/windows-sysmon.log|XmlWinEventLog|XmlWinEventLog:Microsoft-Windows-Sysmon/Operational|main"

  # Rule: Registry Keys Used For Persistence (T1547.001)
  "attack_techniques/T1547.001/atomic_red_team/windows-sysmon.log|XmlWinEventLog|XmlWinEventLog:Microsoft-Windows-Sysmon/Operational|main"

  # Rule: Deleting Shadow Copies (T1490)
  "attack_techniques/T1490/known_services_killed_by_ransomware/windows-xml.log|XmlWinEventLog|XmlWinEventLog:System|main"

  # Rule: Windows Event Log Cleared (T1070.001)
  "attack_techniques/T1070.001/windows_event_log_cleared/windows-xml.log|XmlWinEventLog|XmlWinEventLog:Security|main"

  # Rule: Windows Eventlog Cleared Via Wevtutil (T1070.001)
  "attack_techniques/T1070.001/atomic_red_team/windows-sysmon.log|XmlWinEventLog|XmlWinEventLog:Microsoft-Windows-Sysmon/Operational|main"

  # Rule: Windows Scheduled Task with Suspicious Command (T1053.005)
  "attack_techniques/T1053.005/winevent_scheduled_task_created_to_spawn_shell/windows-xml.log|XmlWinEventLog|XmlWinEventLog:Security|main"

  # Rule: Windows OS Credential Dumping with Procdump (T1003.001)
  "attack_techniques/T1003.001/atomic_red_team/windows-sysmon.log|XmlWinEventLog|XmlWinEventLog:Microsoft-Windows-Sysmon/Operational|main"

  # Rule: Attacker Tools On Endpoint (T1595)
  "attack_techniques/T1595/attacker_scan_tools/windows-sysmon.log|XmlWinEventLog|XmlWinEventLog:Microsoft-Windows-Sysmon/Operational|main"

  # ── Linux ──
  # Rule: Linux APT Privilege Escalation (T1548)
  "attack_techniques/T1548/apt/sysmon_linux.log|sysmon:linux|Syslog:Linux-Sysmon/Operational|main"

  # ── AWS Cloud ──
  # Rule: AWS Defense Evasion Delete CloudTrail (T1562.008)
  "attack_techniques/T1562.008/aws_delete_cloudtrail/amazon-cloudtrail.log|aws:cloudtrail|aws_cloudtrail|main"

  # Rule: AWS IAM AccessDenied Discovery Events
  "suspicious_behaviour/abnormally_high_cloud_instances_launched/cloudtrail_behavioural_detections.json|aws:cloudtrail|aws_cloudtrail|main"

  # Rule: AWS CreateAccessKey
  "attack_techniques/T1136.003/aws_createaccesskey/aws_cloudtrail_events.json|aws:cloudtrail|aws_cloudtrail|main"
)

echo "========================================="
echo " Ingesting Attack Datasets"
echo "========================================="

ingest_count=0
fail_count=0

for entry in "${DATASETS[@]}"; do
  IFS='|' read -r dataset_path sourcetype source index <<< "$entry"
  full_path="${ATTACK_DATA}/datasets/${dataset_path}"

  echo ""
  echo "── Dataset: ${dataset_path}"

  # Pull this specific file from LFS if not already
  if [ ! -f "$full_path" ] || [ "$(wc -c < "$full_path")" -lt 200 ]; then
    echo "   Pulling from Git LFS..."
    (cd "$ATTACK_DATA" && git lfs pull --include="datasets/${dataset_path}") 2>/dev/null || true
  fi

  if [ ! -f "$full_path" ]; then
    echo "   SKIP: File not found after LFS pull"
    ((fail_count++)) || true
    continue
  fi

  file_size=$(wc -c < "$full_path" | tr -d ' ')
  echo "   Size: ${file_size} bytes | Sourcetype: ${sourcetype} | Source: ${source}"

  # Create the index if it doesn't exist
  curl -ks -u "$SPLUNK_AUTH" \
    "${SPLUNK_URL}/servicesNS/admin/search/data/indexes" \
    -d "name=${index}" 2>/dev/null || true

  # Ingest via HEC (raw endpoint, chunked for large files)
  http_code=$(curl -ks -o /dev/null -w "%{http_code}" \
    "${HEC_URL}?sourcetype=${sourcetype}&source=${source}&index=${index}" \
    -H "Authorization: Splunk ${HEC_TOKEN}" \
    -H "Content-Type: text/plain" \
    --data-binary "@${full_path}")

  if [ "$http_code" = "200" ]; then
    echo "   OK (HTTP ${http_code})"
    ((ingest_count++)) || true
  else
    echo "   FAILED (HTTP ${http_code})"
    ((fail_count++)) || true
  fi
done

echo ""
echo "========================================="
echo " Ingestion Complete"
echo " Success: ${ingest_count} | Failed: ${fail_count}"
echo "========================================="
echo ""
echo " Open http://localhost:8000 to explore the data."
echo " Try: index=main sourcetype=XmlWinEventLog | head 10"
echo "========================================="
