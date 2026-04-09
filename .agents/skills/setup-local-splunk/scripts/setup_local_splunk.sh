#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:?Usage: $0 <target_directory>}"
TARGET_DIR="$(cd "$(dirname "$TARGET_DIR")" && pwd)/$(basename "$TARGET_DIR")"

echo "========================================="
echo " Splunk Lab Setup → ${TARGET_DIR}"
echo "========================================="

# ── Create directory structure ──
mkdir -p "${TARGET_DIR}"/{apps,data,repos}
cd "${TARGET_DIR}"

# ── Create .env ──
if [ ! -f .env ]; then
cat > .env << 'ENVEOF'
SPLUNK_PASSWORD=ChangeMeN0w!
SPLUNK_HEC_TOKEN=a1b2c3d4-e5f6-7890-abcd-ef1234567890
ENVEOF
echo "[+] Created .env"
fi

source .env

# ── Create docker-compose.yml ──
cat > docker-compose.yml << 'DCEOF'
services:
  splunk:
    platform: linux/amd64
    image: splunk/splunk:latest
    container_name: splunk-lab
    hostname: splunk-lab
    environment:
      - SPLUNK_START_ARGS=--accept-license
      - SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com
      - SPLUNK_PASSWORD=${SPLUNK_PASSWORD:-ChangeMeN0w!}
      - SPLUNK_HEC_TOKEN=${SPLUNK_HEC_TOKEN:-a1b2c3d4-e5f6-7890-abcd-ef1234567890}
    ports:
      - "8000:8000"
      - "8088:8088"
      - "8089:8089"
      - "9997:9997"
    volumes:
      - splunk-var:/opt/splunk/var
      - splunk-etc:/opt/splunk/etc
      - ./apps:/opt/splunk/etc/apps/custom_apps
      - ./data:/tmp/data
    restart: unless-stopped

volumes:
  splunk-var:
  splunk-etc:
DCEOF
echo "[+] Created docker-compose.yml"

# ── Start Splunk ──
echo ""
echo "[1/5] Starting Splunk container..."
docker compose up -d
echo "Waiting for Splunk to be ready..."
until curl -ks "https://localhost:8089/services/server/info?output_mode=json" \
  -u "admin:${SPLUNK_PASSWORD}" 2>/dev/null | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; do
  printf "."
  sleep 5
done
echo ""
echo "Splunk is ready!"

# ── Clone security_content ──
echo ""
echo "[2/5] Cloning splunk/security_content..."
if [ ! -d "repos/security_content" ]; then
  git clone --depth 1 https://github.com/splunk/security_content.git repos/security_content
fi

# ── Build ESCU ──
echo ""
echo "[3/5] Building ESCU app..."
cd repos/security_content

PYTHON_311=""
if command -v mise &>/dev/null; then
  mise install python@3.11 2>/dev/null || true
  PYTHON_311="$(mise where python@3.11 2>/dev/null)/bin/python3.11" || true
fi
if [ -z "$PYTHON_311" ] || [ ! -x "$PYTHON_311" ]; then
  PYTHON_311="$(command -v python3.11 2>/dev/null || command -v python3)"
fi

"$PYTHON_311" -m venv .venv 2>/dev/null || true
source .venv/bin/activate
pip install -q contentctl

if [ ! -d "external_repos/atomic-red-team" ]; then
  git clone --depth 1 --single-branch https://github.com/redcanaryco/atomic-red-team external_repos/atomic-red-team
fi
if [ ! -d "external_repos/cti" ]; then
  git clone --depth 1 --single-branch https://github.com/mitre/cti external_repos/cti
fi

contentctl build --enrichments
deactivate
cd "${TARGET_DIR}"

ESCU_APP=$(find repos/security_content/dist -name "*.tar.gz" -type f | head -1)
echo "Built: ${ESCU_APP}"

# ── Install ESCU ──
echo ""
echo "[4/5] Installing ESCU on Splunk..."
docker cp "${ESCU_APP}" splunk-lab:/tmp/escu.tar.gz
docker exec -u splunk splunk-lab /opt/splunk/bin/splunk install app /tmp/escu.tar.gz -auth "admin:${SPLUNK_PASSWORD}"

echo "Restarting Splunk..."
docker exec -u splunk splunk-lab /opt/splunk/bin/splunk restart -auth "admin:${SPLUNK_PASSWORD}" &
sleep 30
until curl -ks "https://localhost:8089/services/server/info?output_mode=json" \
  -u "admin:${SPLUNK_PASSWORD}" 2>/dev/null | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; do
  printf "."
  sleep 5
done
echo ""

RULE_COUNT=$(curl -ks "https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0&search=ESCU" \
  -u "admin:${SPLUNK_PASSWORD}" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entry',[])))" 2>/dev/null || echo "?")
echo "ESCU loaded: ${RULE_COUNT} saved searches"

# ── Clone attack_data ──
echo ""
echo "[5/5] Cloning splunk/attack_data..."
git lfs install --skip-smudge 2>/dev/null || true
if [ ! -d "repos/attack_data" ]; then
  git clone --depth 1 https://github.com/splunk/attack_data.git repos/attack_data
fi

# ── Enable HEC ──
curl -ks -u "admin:${SPLUNK_PASSWORD}" \
  "https://localhost:8089/servicesNS/nobody/splunk_httpinput/data/inputs/http/http" \
  -X POST -d "disabled=0" > /dev/null 2>&1 || true

curl -ks -u "admin:${SPLUNK_PASSWORD}" \
  "https://localhost:8089/servicesNS/nobody/splunk_httpinput/data/inputs/http" \
  -X POST \
  -d "name=attack_data" \
  -d "token=${SPLUNK_HEC_TOKEN}" \
  -d "index=main" \
  -d "disabled=0" > /dev/null 2>&1 || true

echo ""
echo "========================================="
echo " Setup Complete!"
echo "========================================="
echo ""
echo " Web UI:   http://localhost:8000"
echo " Login:    admin / ${SPLUNK_PASSWORD}"
echo " HEC:      https://localhost:8088"
echo " Rules:    ${RULE_COUNT} ESCU detections"
echo ""
echo " Next steps:"
echo "   1. Download TAs from Splunkbase (Windows, Sysmon, CIM)"
echo "   2. Install TAs: docker cp <file> splunk-lab:/tmp/ta.tgz && docker exec -u splunk splunk-lab /opt/splunk/bin/splunk install app /tmp/ta.tgz -auth admin:${SPLUNK_PASSWORD}"
echo "   3. Restart: docker exec -u splunk splunk-lab /opt/splunk/bin/splunk restart -auth admin:${SPLUNK_PASSWORD}"
echo "   4. Ingest data: ./ingest_data.sh"
echo "========================================="
