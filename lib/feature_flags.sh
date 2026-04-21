#!/usr/bin/env bash
# feature_flags.sh — lê flags do ~/.claude/meta-ads-pro/flags.yaml
#
# FU-3 fix: delega pro script Python standalone que recebe args via argv
# (nunca via heredoc). Seguro contra flag names e defaults user-controlled.

set -euo pipefail

FLAGS_FILE="${FLAGS_FILE:-${HOME}/.claude/meta-ads-pro/flags.yaml}"

_FEATURE_FLAGS_PY="$(dirname "${BASH_SOURCE[0]}")/_py/feature_flags_get.py"

get_flag() {
  local name="$1" default="${2:-false}"
  python3 "$_FEATURE_FLAGS_PY" \
    --file "$FLAGS_FILE" \
    --name "$name" \
    --default "$default"
}
