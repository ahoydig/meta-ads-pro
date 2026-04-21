#!/usr/bin/env bash
# tests/12-import-existing.sh — valida integração de lib/_py/import_existing.py
#
# Cobertura (tudo offline — via urllib monkey-patch):
#   1. --help mostra uso
#   2. falta de args obrigatórios → exit 2 (argparse)
#   3. schema do JSON gerado: imported_at, ad_account_id, source, campaigns,
#      leadgen_forms, summary; campanhas têm adsets, adsets têm ads
#   4. summary contagens batem com dados mockados
#   5. redact token — error logs não vazam access_token
#   6. mkdir idempotente — rodar 2x no mesmo out_dir gera 2 arquivos distintos
#
# Roda sem META_ACCESS_TOKEN (usa mock). shellcheck clean, bash 3.2.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMPORT_PY="$PLUGIN_ROOT/lib/_py/import_existing.py"

PASS=0; FAIL=0
_pass() { echo "✓ $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$(( FAIL + 1 )); }

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/import-existing-test.XXXXXX")
cleanup_all() { local rc=$?; rm -rf "$TMPROOT" 2>/dev/null || true; exit $rc; }
trap cleanup_all EXIT INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Mock runner — injeta stub de urllib.request.urlopen pra responder Graph API
# ─────────────────────────────────────────────────────────────────────────────
MOCK_RUNNER="$TMPROOT/run_mock.py"
cat > "$MOCK_RUNNER" <<'PY'
"""Wrapper que monkey-patcha urllib.request.urlopen antes de rodar
import_existing.py, simulando Graph API offline.

Dados mockados:
  - 2 campanhas
  - campanha 1 → 2 adsets; adset 1 → 3 ads; adset 2 → 1 ad
  - campanha 2 → 1 adset; adset → 0 ads
  - page passed → 2 leadgen_forms
  Totais: 2 camps, 3 adsets, 4 ads, 2 forms
"""
import io
import json
import runpy
import sys
import urllib.parse
import urllib.request


def _route(url: str):
    parsed = urllib.parse.urlparse(url)
    path = parsed.path.rsplit('/', 1)[-1]
    parent = parsed.path.rstrip('/').split('/')[-2] if '/' in parsed.path.rstrip('/') else ''

    # /act_X/campaigns
    if path == "campaigns" and parent.startswith("act_"):
        return {"data": [
            {"id": "100", "name": "C1", "status": "ACTIVE", "objective": "OUTCOME_LEADS"},
            {"id": "200", "name": "C2", "status": "PAUSED", "objective": "OUTCOME_TRAFFIC"},
        ]}
    # /<camp_id>/adsets
    if path == "adsets":
        if parent == "100":
            return {"data": [
                {"id": "A1", "name": "A1", "status": "ACTIVE"},
                {"id": "A2", "name": "A2", "status": "PAUSED"},
            ]}
        if parent == "200":
            return {"data": [{"id": "A3", "name": "A3", "status": "PAUSED"}]}
        return {"data": []}
    # /<adset_id>/ads
    if path == "ads":
        if parent == "A1":
            return {"data": [
                {"id": "ad1", "name": "ad1", "status": "ACTIVE"},
                {"id": "ad2", "name": "ad2", "status": "ACTIVE"},
                {"id": "ad3", "name": "ad3", "status": "PAUSED"},
            ]}
        if parent == "A2":
            return {"data": [{"id": "ad4", "name": "ad4", "status": "ACTIVE"}]}
        return {"data": []}
    # /<page_id>/leadgen_forms
    if path == "leadgen_forms":
        return {"data": [
            {"id": "F1", "name": "F1", "status": "ACTIVE", "leads_count": 10},
            {"id": "F2", "name": "F2", "status": "ARCHIVED", "leads_count": 0},
        ]}
    return {"data": []}


class _FakeResp:
    def __init__(self, payload):
        self._buf = io.BytesIO(json.dumps(payload).encode("utf-8"))

    def read(self):
        return self._buf.read()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self._buf.close()


def _fake_urlopen(url, timeout=None):  # noqa: ARG001
    return _FakeResp(_route(url))


urllib.request.urlopen = _fake_urlopen

# sys.argv[0] = mock_runner, passa resto pra import_existing.py
import_script = sys.argv[1]
sys.argv = [import_script] + sys.argv[2:]
runpy.run_path(import_script, run_name="__main__")
PY

run_import() {
  python3 "$MOCK_RUNNER" "$IMPORT_PY" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. --help mostra uso (argparse) — sai 0
# ─────────────────────────────────────────────────────────────────────────────
test_help() {
  local out rc=0
  out=$(python3 "$IMPORT_PY" --help 2>&1) || rc=$?
  if (( rc == 0 )) && echo "$out" | grep -q -- "--account" \
    && echo "$out" | grep -q -- "--token" && echo "$out" | grep -q -- "--out"; then
    _pass "test_help"
  else
    _fail "test_help" "rc=$rc out=$out"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Falta de args obrigatórios → exit 2 (argparse convention)
# ─────────────────────────────────────────────────────────────────────────────
test_missing_args_exit_2() {
  local rc=0
  python3 "$IMPORT_PY" 2>/dev/null || rc=$?
  if (( rc == 2 )); then
    _pass "test_missing_args_exit_2 (argparse)"
  else
    _fail "test_missing_args_exit_2" "rc=$rc (esperado 2)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Schema do JSON + 4. summary contagens (casado num único run pra economia)
# ─────────────────────────────────────────────────────────────────────────────
test_schema_and_summary() {
  local out_dir="$TMPROOT/out1" path errs=0
  path=$(run_import --account act_TEST --token FAKE --out "$out_dir" --page 999) || {
    _fail "test_schema_and_summary" "run_import falhou"; return
  }

  [[ -f "$path" ]] || { _fail "test_schema_and_summary" "arquivo não existe: $path"; return; }

  # Top-level keys
  local imported_at acct src n_camps n_adsets n_ads n_forms
  imported_at=$(jq -r '.imported_at // empty' "$path")
  acct=$(jq -r '.ad_account_id // empty' "$path")
  src=$(jq -r '.source // empty' "$path")
  n_camps=$(jq -r '.summary.campaigns // empty' "$path")
  n_adsets=$(jq -r '.summary.adsets // empty' "$path")
  n_ads=$(jq -r '.summary.ads // empty' "$path")
  n_forms=$(jq -r '.summary.forms // empty' "$path")

  [[ -n "$imported_at" ]]    || { errs=$((errs+1)); echo "  ↳ imported_at vazio" >&2; }
  [[ "$acct" == "act_TEST" ]] || { errs=$((errs+1)); echo "  ↳ ad_account_id='$acct'" >&2; }
  [[ "$src" == "pre-plugin" ]] || { errs=$((errs+1)); echo "  ↳ source='$src'" >&2; }
  [[ "$n_camps" == "2" ]]    || { errs=$((errs+1)); echo "  ↳ summary.campaigns=$n_camps" >&2; }
  [[ "$n_adsets" == "3" ]]   || { errs=$((errs+1)); echo "  ↳ summary.adsets=$n_adsets" >&2; }
  [[ "$n_ads" == "4" ]]      || { errs=$((errs+1)); echo "  ↳ summary.ads=$n_ads" >&2; }
  [[ "$n_forms" == "2" ]]    || { errs=$((errs+1)); echo "  ↳ summary.forms=$n_forms" >&2; }

  # Hierarquia: campaigns[].adsets[].ads[]
  local has_nested
  has_nested=$(jq -r '[.campaigns[].adsets[].ads | length] | add' "$path")
  [[ "$has_nested" == "4" ]] || { errs=$((errs+1)); echo "  ↳ nested ads total=$has_nested" >&2; }

  if (( errs == 0 )); then
    _pass "test_schema_and_summary (2c/3as/4ads/2forms)"
  else
    _fail "test_schema_and_summary" "$errs erros"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Redact: token não aparece em logs de erro (simula HTTPError)
# ─────────────────────────────────────────────────────────────────────────────
test_redact_token_in_errors() {
  # Usa o próprio import_existing, mas testa só a função _redact_token
  # via python inline — mais robusto que simular HTTPError real
  local token="SUPER_SECRET_TOKEN_ABC123"
  local out
  out=$(python3 - <<PY 2>&1
import sys
sys.path.insert(0, "$PLUGIN_ROOT/lib/_py")
from import_existing import _redact_token
url = "https://graph.facebook.com/v25.0/act_X/campaigns?fields=id&access_token=$token"
print(_redact_token(url))
PY
)
  if echo "$out" | grep -q "$token"; then
    _fail "test_redact_token_in_errors" "token vazou: $out"
  elif echo "$out" | grep -q "access_token=%2A%2A%2A\|access_token=\*\*\*"; then
    _pass "test_redact_token_in_errors (*** mask)"
  else
    _fail "test_redact_token_in_errors" "token não foi mascarado: $out"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. mkdir idempotente: rodar 2x no mesmo out_dir gera 2 arquivos distintos
# ─────────────────────────────────────────────────────────────────────────────
test_mkdir_idempotent() {
  local out_dir="$TMPROOT/out2"
  local p1 p2
  p1=$(run_import --account act_IDEM --token FAKE --out "$out_dir") || {
    _fail "test_mkdir_idempotent" "run 1 falhou"; return
  }
  # Garante ts diferente
  sleep 1
  p2=$(run_import --account act_IDEM --token FAKE --out "$out_dir") || {
    _fail "test_mkdir_idempotent" "run 2 falhou"; return
  }
  if [[ "$p1" != "$p2" ]] && [[ -f "$p1" ]] && [[ -f "$p2" ]]; then
    _pass "test_mkdir_idempotent (2 arquivos distintos)"
  else
    _fail "test_mkdir_idempotent" "p1=$p1 p2=$p2"
  fi
}

# ── runner ───────────────────────────────────────────────────────────────────
for t in \
  test_help \
  test_missing_args_exit_2 \
  test_schema_and_summary \
  test_redact_token_in_errors \
  test_mkdir_idempotent
do
  $t
done

echo ""
echo "import-existing: ${PASS} passou, ${FAIL} falhou"
[[ "$FAIL" -eq 0 ]]
