---
name: setup-local-splunk
description: Set up a local Splunk Enterprise lab with ESCU detections and attack datasets for SIEM migration testing. Use when spinning up a Splunk instance, testing detection rule migration, ingesting Splunk attack data, exporting macros/lookups, or when asked about Splunk lab setup.
---

# Setup Local Splunk Lab

Spin up a local Splunk Enterprise instance via Docker with 2000+ ESCU detection rules, attack datasets, and all macros/lookups pre-configured. Used for SIEM rule migration testing.

## Agent Directives

> **IMPORTANT**: After the setup script finishes, you MUST explicitly tell the user that they need to manually download three Technology Add-ons from Splunkbase before detections will work. Field extraction depends on these TAs — without them, ingested logs remain raw XML and no detection rules will fire. Do NOT proceed to data ingestion or rule export without confirming the user has installed the TAs and restarted Splunk.
>
> Say something like:
> "Setup is complete, but there is one manual step you need to do before we can proceed. Splunk needs three Technology Add-ons for field extraction that can only be downloaded from Splunkbase (requires a free account). Without these, detection rules won't fire because fields like EventCode, Image, and CommandLine won't be extracted from the raw logs. Please download these three and let me know when you have them:
> 1. **Splunk Add-on for Microsoft Windows** — https://splunkbase.splunk.com/app/742
> 2. **Splunk Add-on for Sysmon** — https://splunkbase.splunk.com/app/5709
> 3. **Splunk Common Information Model (CIM)** — https://splunkbase.splunk.com/app/1621
>
> Once downloaded, I'll install them for you."

## Prerequisites

- Docker & Docker Compose
- Git LFS (`brew install git-lfs && git lfs install --skip-smudge`)
- Python 3.11 via `mise` (`mise install python@3.11`). **`contentctl` does NOT work with Python 3.14+** — it crashes with `AttributeError: __class_getitem__`.
- Free Splunkbase account for downloading Technology Add-ons

## Quick Start

From the repo root (`~/projects/Splunk_lab`):

```bash
./setup.sh
```

This will:
1. Start Splunk Enterprise via `docker compose up` (runs under Rosetta on Apple Silicon)
2. Clone `splunk/security_content` and enrichment repos (`atomic-red-team`, `mitre/cti`)
3. Build ESCU app via `contentctl build --enrichments` using Python 3.11
4. Install ESCU on Splunk via `docker cp` + `splunk install app` CLI
5. Clone `splunk/attack_data` for test datasets (Git LFS, smudge-skipped)
6. Enable HEC and create a token for data ingestion

### Known Timing

- Initial Splunk startup: ~60-90s (Rosetta emulation on Apple Silicon)
- `contentctl build --enrichments`: ~15-20s
- Splunk restart after ESCU install: ~60-90s (background restart, polled for readiness)
- Total: ~5-10 minutes depending on git clone speeds

## Critical Implementation Details

### Splunk Health/Readiness Check

**Do NOT use** `/services/server/health/splunkd` — it returns XML regardless of headers and `grep` for JSON status strings will never match.

**Use instead:**
```bash
curl -ks "https://localhost:8089/services/server/info?output_mode=json" \
  -u "admin:ChangeMeN0w!" | python3 -c "import sys,json; json.load(sys.stdin)"
```
This returns valid JSON when Splunk is ready and fails otherwise. Use it in an `until` loop.

### ESCU App Installation

**Do NOT use** the Splunk REST API multipart upload (`/services/apps/local` with `-F appfile=@...`) — it fails silently.

**Use instead:**
```bash
docker cp <escu_tarball> splunk-lab:/tmp/escu.tar.gz
docker exec -u splunk splunk-lab /opt/splunk/bin/splunk install app /tmp/escu.tar.gz -auth "admin:ChangeMeN0w!"
```

### Splunk Restart After App Install

Run restart in background (`&`) because it blocks the terminal, then poll the info endpoint:
```bash
docker exec -u splunk splunk-lab /opt/splunk/bin/splunk restart -auth "admin:ChangeMeN0w!" &
sleep 30
until curl -ks "https://localhost:8089/services/server/info?output_mode=json" \
  -u "admin:ChangeMeN0w!" 2>/dev/null | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; do
  sleep 5
done
```

### contentctl Build Requirements

`contentctl build --enrichments` requires two external repos cloned into `repos/security_content/external_repos/`:
```bash
git clone --depth 1 --single-branch https://github.com/redcanaryco/atomic-red-team external_repos/atomic-red-team
git clone --depth 1 --single-branch https://github.com/mitre/cti external_repos/cti
```
Without these, the build fails with missing enrichment data.

## Manual Step: Install Technology Add-ons (REQUIRED)

**This step cannot be automated.** Without these TAs, ingested logs stay as raw XML and detection rules will not fire (fields like `EventCode`, `Image`, `CommandLine`, `process_name` are not extracted).

After setup, download these from Splunkbase (free account required) and install:

| Add-on | URL | Purpose |
|--------|-----|---------|
| Splunk Add-on for Microsoft Windows | https://splunkbase.splunk.com/app/742 | Windows Event Log field extraction |
| Splunk Add-on for Sysmon | https://splunkbase.splunk.com/app/5709 | Sysmon field extraction |
| Splunk Common Information Model | https://splunkbase.splunk.com/app/1621 | CIM data models |

Install each downloaded `.spl`/`.tgz` file:

```bash
docker cp <downloaded_file> splunk-lab:/tmp/ta.tgz
docker exec -u splunk splunk-lab /opt/splunk/bin/splunk install app /tmp/ta.tgz -auth admin:ChangeMeN0w!
```

Then restart Splunk once:

```bash
docker exec -u splunk splunk-lab /opt/splunk/bin/splunk restart -auth admin:ChangeMeN0w!
```

## Ingesting Attack Data

After setup and TA installation, ingest test datasets:

```bash
./ingest_data.sh
```

The script pulls specific datasets from Git LFS and ingests them via HEC. Edit `ingest_data.sh` to add/remove datasets.

## Exporting for SIEM Migrations

### Export Macros (Splunk export format)

```bash
curl -ks -u "admin:ChangeMeN0w!" \
  "https://localhost:8089/servicesNS/-/-/admin/macros?output_mode=json&count=0" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
macros = [{'result': {'title': e['name'], 'definition': e['content'].get('definition','')}}
          for e in d.get('entry', [])]
with open('macros.json', 'w') as f:
    json.dump(macros, f, indent=2)
print(f'Exported {len(macros)} macros')
"
```

The output format (`{"result": {"title": ..., "definition": ...}}`) is what the Kibana SIEM Migrations UI expects for macro upload. A flat array of `{name, definition}` objects will fail with "non-object entries".

### Export Lookups

```bash
mkdir -p lookups
for f in $(docker exec splunk-lab ls /opt/splunk/etc/apps/DA-ESS-ContentUpdate/lookups/ | grep .csv); do
  docker cp "splunk-lab:/opt/splunk/etc/apps/DA-ESS-ContentUpdate/lookups/$f" "lookups/$f"
done
```

### Query Detections by Analytic Story

In the Splunk Search bar (http://localhost:8000):

```spl
| rest /servicesNS/-/-/saved/searches splunk_server=local count=0
| where match(title, "^ESCU.*Rule$")
| where like('action.escu.analytic_story', "%YOUR_STORY_NAME%")
| table title, search, action.escu.analytic_story
```

List all stories with detection counts:

```spl
| rest /servicesNS/-/-/saved/searches splunk_server=local count=0
| where match(title, "^ESCU.*Rule$")
| spath input=action.escu.analytic_story
| mvexpand "{}"
| rename "{}" as analytic_story
| stats count by analytic_story
| sort -count
```

## Access Details

| Service | URL | Credentials |
|---------|-----|-------------|
| Splunk Web UI | http://localhost:8000 | admin / ChangeMeN0w! |
| Splunk Management API | https://localhost:8089 | admin / ChangeMeN0w! |
| HEC Endpoint | https://localhost:8088 | Token: a1b2c3d4-e5f6-7890-abcd-ef1234567890 |

## Teardown

```bash
./teardown.sh            # Interactive: stop, optionally delete volumes
docker compose down      # Stop, preserve data
docker compose down -v   # Stop and delete all data
```

To fully clean up (including cloned repos):
```bash
docker compose down -v && rm -rf repos apps data exported_rules
```

## Architecture Notes

- `splunk/splunk` Docker image is Intel-only; uses `platform: linux/amd64` for Rosetta emulation on Apple Silicon
- Splunk 10.x requires `SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com` in addition to `SPLUNK_START_ARGS=--accept-license`
- ESCU is built from source via `contentctl build --enrichments` (requires `atomic-red-team` and `mitre/cti` repos in `external_repos/`)
- Attack datasets use Git LFS; files are pulled on-demand per dataset via `git lfs pull --include=<path>`
- HEC token is created programmatically; both the global HEC input and a named token must be enabled

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `no matching manifest for linux/arm64/v8` | Add `platform: linux/amd64` to docker-compose.yml |
| `License not accepted` | Add `SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com` env var |
| `contentctl` crashes with `AttributeError: __class_getitem__` | Use Python 3.11 via `mise`, not system Python 3.14+ |
| `contentctl build --enrichments` fails with missing data | Clone `atomic-red-team` and `mitre/cti` into `external_repos/` |
| Health check loops forever | Use `/services/server/info?output_mode=json`, NOT `/services/server/health/splunkd` (returns XML) |
| ESCU install via REST API fails silently | Use `docker cp` + `splunk install app` CLI instead of curl multipart upload |
| Splunk restart hangs terminal | Run restart with `&` (background), then poll info endpoint |
| Fields not extracted (no EventCode, Image, etc.) | Install the Windows TA, Sysmon TA, and CIM from Splunkbase |
| Macros upload fails with "non-object entries" | Export macros in Splunk format: `[{"result": {"title": ..., "definition": ...}}]` |
