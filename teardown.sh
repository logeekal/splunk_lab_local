#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Stopping Splunk lab..."
docker compose down

read -p "Remove persistent volumes (all Splunk data)? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  docker compose down -v
  echo "Volumes removed."
else
  echo "Volumes preserved. Data will persist on next startup."
fi
