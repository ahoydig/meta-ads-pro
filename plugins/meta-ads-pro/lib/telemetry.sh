#!/usr/bin/env bash
# telemetry.sh — wrapper pra lib/_py/telemetry_log.py

set -euo pipefail

_TELEMETRY_PY="$(dirname "${BASH_SOURCE[0]}")/_py/telemetry_log.py"

telemetry_log() {
  # respeita flag opt-out (env var ou CLAUDE.md flag)
  [[ "${META_ADS_NO_TELEMETRY:-}" == "1" ]] && return 0
  python3 "$_TELEMETRY_PY" "$@" 2>/dev/null || true
}
