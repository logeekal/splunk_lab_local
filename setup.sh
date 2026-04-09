#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source .env 2>/dev/null || true
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-ChangeMeN0w!}"
SPLUNK_URL="https://localhost:8089"
SPLUNK_AUTH="admin:${SPLUNK_PASSWORD}"

echo "========================================="
echo " Splunk Lab Setup"
echo "========================================="

# ── Step 1: Create directories ──
echo ""
echo "[1/6] Creating directories..."
mkdir -p apps data repos

# ── Step 2: Start Splunk ──
echo ""
echo "[2/6] Starting Splunk container..."
docker compose up -d
echo "Waiting for Splunk to be ready..."
until curl -ks "${SPLUNK_URL}/services/server/health/splunkd" \
  -u "$SPLUNK_AUTH" 2>/dev/null | grep -q '"status":"green"\|"status":"yellow"'; do
  printf "."
  sleep 5
done
echo ""
echo "Splunk is ready!"

# ── Step 3: Clone security_content & build ESCU ──
echo ""
echo "[3/6] Setting up Splunk Security Content (ESCU)..."
if [ ! -d "repos/security_content" ]; then
  git clone --depth 1 https://github.com/splunk/security_content.git repos/security_content
else
  echo "  security_content already cloned, pulling latest..."
  git -C repos/security_content pull --ff-only || true
fi

echo "  Building ESCU app..."
cd repos/security_content
python3 -m venv .venv 2>/dev/null || true
source .venv/bin/activate
pip install -q contentctl
contentctl build --enrichments
deactivate
cd "$SCRIPT_DIR"

ESCU_APP=$(find repos/security_content/dist -name "*.tar.gz" -type f | head -1)
if [ -z "$ESCU_APP" ]; then
  echo "  ERROR: ESCU app not found in dist/. Build may have failed."
  exit 1
fi
echo "  Built: $ESCU_APP"

# ── Step 4: Install ESCU on Splunk ──
echo ""
echo "[4/6] Installing ESCU app on Splunk..."
curl -ks -u "$SPLUNK_AUTH" \
  "${SPLUNK_URL}/services/apps/local" \
  -F "name=$(basename "$ESCU_APP")" \
  -F "filename=true" \
  -F "update=true" \
  -F "appfile=@${ESCU_APP}" > /dev/null

echo "  ESCU installed. Restarting Splunk..."
curl -ks -u "$SPLUNK_AUTH" \
  "${SPLUNK_URL}/services/server/control/restart" \
  -X POST > /dev/null
sleep 10
until curl -ks "${SPLUNK_URL}/services/server/health/splunkd" \
  -u "$SPLUNK_AUTH" 2>/dev/null | grep -q '"status":"green"\|"status":"yellow"'; do
  printf "."
  sleep 5
done
echo ""
echo "  Splunk restarted with ESCU."

# ── Step 5: Clone attack_data ──
echo ""
echo "[5/6] Setting up attack_data repository..."
if [ ! -d "repos/attack_data" ]; then
  git lfs install --skip-smudge 2>/dev/null || true
  git clone --depth 1 https://github.com/splunk/attack_data.git repos/attack_data
else
  echo "  attack_data already cloned."
fi

# ── Step 6: Enable HEC ──
echo ""
echo "[6/6] Enabling HTTP Event Collector..."
curl -ks -u "$SPLUNK_AUTH" \
  "${SPLUNK_URL}/servicesNS/admin/splunk_httpinput/data/inputs/http/http" \
  -X POST \
  -d "disabled=0" > /dev/null 2>&1 || true

echo ""
echo "========================================="
echo " Setup Complete!"
echo "========================================="
echo ""
echo " Web UI:   http://localhost:8000"
echo " Login:    admin / ${SPLUNK_PASSWORD}"
echo " HEC:      https://localhost:8088"
echo " HEC Token: $(grep SPLUNK_HEC_TOKEN .env | cut -d= -f2)"
echo ""
echo " Next: run ./ingest_data.sh to load test datasets"
echo "========================================="
