#!/usr/bin/env bash
# tests/09-publicos.sh — listagem mínima de custom audiences (CP3, Task 3b.3.6).
#
# Skip gracioso quando META_ACCESS_TOKEN ausente. Apenas GETs (não cria nada).
# Bash 3.2 portable.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "SKIP: sem META_ACCESS_TOKEN — 09-publicos não roda sem token live"
  exit 0
fi

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

PASS=0
FAIL=0

_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }

test_01_list_custom_audiences() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/customaudiences?fields=id,name&limit=3") \
    || _fail test_01_list_custom_audiences "graph_api falhou"
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || _fail test_01_list_custom_audiences "response.data não é array"
  _pass test_01_list_custom_audiences
}

test_02_list_saved_audiences() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/saved_audiences?fields=id,name&limit=3") \
    || _fail test_02_list_saved_audiences "graph_api falhou"
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || _fail test_02_list_saved_audiences "response.data não é array"
  _pass test_02_list_saved_audiences
}

test_01_list_custom_audiences
test_02_list_saved_audiences

echo ""
echo "09-publicos: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
