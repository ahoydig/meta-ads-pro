#!/usr/bin/env bash
# tests/11-insights.sh — account insights mínimo (CP3, Task 3b.3.6).
#
# Skip gracioso quando META_ACCESS_TOKEN ausente. Apenas GETs.
# Bash 3.2 portable.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "SKIP: sem META_ACCESS_TOKEN — 11-insights não roda sem token live"
  exit 0
fi

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

PASS=0
FAIL=0

_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }

test_01_account_insights_7d() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/insights?date_preset=last_7d&fields=spend,impressions") \
    || _fail test_01_account_insights_7d "graph_api falhou"
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || _fail test_01_account_insights_7d "response.data não é array"
  _pass test_01_account_insights_7d
}

test_01_account_insights_7d

echo ""
echo "11-insights: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
