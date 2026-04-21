#!/usr/bin/env bash
# tests/10-regras.sh — listagem mínima de automated rules (CP3, Task 3b.3.6).
#
# Skip gracioso quando META_ACCESS_TOKEN ausente. Apenas GETs.
# Bash 3.2 portable.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "SKIP: sem META_ACCESS_TOKEN — 10-regras não roda sem token live"
  exit 0
fi

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

PASS=0
FAIL=0

_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }

test_01_list_rules() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/adrules_library?fields=id,name&limit=3") \
    || _fail test_01_list_rules "graph_api falhou"
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || _fail test_01_list_rules "response.data não é array"
  _pass test_01_list_rules
}

test_01_list_rules

echo ""
echo "10-regras: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
