#!/usr/bin/env bash
# feature_flags.sh — lê flags do ~/.claude/meta-ads-pro/flags.yaml

set -euo pipefail

FLAGS_FILE="${FLAGS_FILE:-${HOME}/.claude/meta-ads-pro/flags.yaml}"

get_flag() {
  local name="$1" default="${2:-false}"
  [[ -f "$FLAGS_FILE" ]] || { echo "$default"; return; }
  python3 - <<PYEOF
import yaml
try:
    with open('$FLAGS_FILE') as f:
        d = yaml.safe_load(f) or {}
    print(str(d.get('$name', '$default')).lower())
except Exception:
    print('$default')
PYEOF
}
