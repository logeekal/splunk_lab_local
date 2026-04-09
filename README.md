# Splunk Lab - Detection Rule Migration Testing

Local Splunk Enterprise instance for testing SIEM rule migration from SPL to ES|QL.

## Prerequisites

- Docker & Docker Compose
- Git LFS (`brew install git-lfs`)
- Python 3.11+

## Quick Start

```bash
# 1. Start Splunk + install ESCU + clone repos
./setup.sh

# 2. Ingest attack datasets
./ingest_data.sh

# 3. Open Splunk UI
open http://localhost:8000
# Login: admin / ChangeMeN0w!

# 4. Export rules for migration testing
./export_rules.sh
```

## What Gets Installed

| Component | Purpose |
|-----------|---------|
| Splunk Enterprise (Docker) | SIEM platform |
| ESCU (DA-ESS-ContentUpdate) | 2000+ detection rules, macros, lookups |
| attack_data (Git LFS) | Curated attack datasets for testing |

## Detection Rules Covered

### Windows Endpoint
- Malicious PowerShell - Encoded Command (T1027)
- Registry Keys Used For Persistence (T1547.001)
- Windows Scheduled Task with Suspicious Command (T1053.005)
- Windows OS Credential Dumping with Procdump (T1003.001)
- Attacker Tools On Endpoint (T1595)

### Windows Defense Evasion
- Windows Event Log Cleared (T1070.001)
- Windows Eventlog Cleared Via Wevtutil (T1070.001)

### Ransomware / Impact
- Deleting Shadow Copies / Services Stop (T1490)

### Linux
- Linux APT Privilege Escalation (T1548)

### AWS Cloud
- AWS Defense Evasion Delete CloudTrail (T1562.008)
- AWS IAM AccessDenied Discovery Events (T1580)
- AWS CreateAccessKey (T1136.003)

## File Structure

```
Splunk_lab/
├── docker-compose.yml    # Splunk container definition
├── .env                  # Credentials (change before production use)
├── setup.sh              # Full setup: start Splunk, build & install ESCU
├── ingest_data.sh        # Ingest attack datasets via HEC
├── export_rules.sh       # Export rules, macros, lookups as JSON
├── teardown.sh           # Stop and optionally clean up
├── repos/                # Cloned repositories (created by setup.sh)
│   ├── security_content/ # Splunk Security Content (ESCU source)
│   └── attack_data/      # Attack datasets (Git LFS)
├── apps/                 # Custom Splunk apps (mounted into container)
├── data/                 # Shared data directory (mounted at /tmp/data)
└── exported_rules/       # Exported rule JSON files (created by export_rules.sh)
```

## Ports

| Port | Service |
|------|---------|
| 8000 | Splunk Web UI |
| 8088 | HTTP Event Collector (HEC) |
| 8089 | Splunk Management API |
| 9997 | Splunk Forwarder Receiving |

## Teardown

```bash
./teardown.sh
```
