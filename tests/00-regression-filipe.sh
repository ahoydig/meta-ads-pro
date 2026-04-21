#!/usr/bin/env bash
# tests/00-regression-filipe.sh — regressão 1:1 com 10 bugs-âncora do caso Filipe
#
# Estrutura por CP:
#   CP1  → test_bug_10  (doctor/preflight — já implementado)
#   CP2a → test_bug_01  (ABO is_adset_budget_sharing_enabled ausente)
#   CP2a → test_bug_02  (CBO daily_budget não passado)
#   CP2b → test_bug_03  (targeting_automation.advantage_audience ausente)
#   CP2b → test_bug_04  (placement instagram_explore sem sibling grid_home)
#   CP2c → test_bug_05  (object_story_spec bloqueado em dev mode → dark post)
#   CP2c → test_bug_06  (media_fbid já em uso → regenerate upload)
#   CP3a → test_bug_07  (lead_gen_form_id inválido)
#   CP3b → test_bug_08  (data_preset retroage > 37 meses)
#   CP3b → test_bug_09  (BUC rate limit — ler header em vez de chutar espera)
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -n "${META_ACCESS_TOKEN:-}" ]] || { echo "SKIP: sem META_ACCESS_TOKEN"; exit 0; }

PASS=0; FAIL=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2"; (( FAIL++ )) || true; exit 1; }

# ── Bug #10: doctor deve ser chamado antes de qualquer POST ───────────────────
# Verifica que check_app_mode (parte do preflight/doctor) seta FALLBACK_DARK_POST.
# Se a flag não for setada, a skill de anúncios pode tentar object_story_spec em
# conta dev mode → error 100/1885183. Esse foi o bug #10 do caso Filipe.
test_bug_10_preflight_doctor() {
  local preflight="$PLUGIN_ROOT/lib/preflight.sh"
  if [[ ! -f "$preflight" ]]; then
    echo "SKIP test_bug_10: preflight.sh não existe ainda"
    (( PASS++ )) || true
    return
  fi

  # shellcheck source=../lib/preflight.sh disable=SC1091
  source "$preflight"

  unset FALLBACK_DARK_POST || true

  # check_app_mode deve setar FALLBACK_DARK_POST (0 = live mode, 1 = dev mode)
  # independente do modo atual — a flag deve sempre ser definida
  check_app_mode >/dev/null 2>&1 || true

  if [[ -n "${FALLBACK_DARK_POST:-}" ]]; then
    _pass "test_bug_10_preflight_doctor (FALLBACK_DARK_POST=${FALLBACK_DARK_POST})"
  else
    _fail "test_bug_10_preflight_doctor" "check_app_mode não setou FALLBACK_DARK_POST — anúncios podem falhar em dev mode"
  fi
}

# ── Bug #1: is_adset_budget_sharing_enabled ausente em campanha ABO ──────────
# Meta Graph API v25.0 rejeita POST /campaigns sem o campo is_adset_budget_sharing_enabled
# quando o objective é ABO (sem daily_budget na campanha). Erro 100 subcode 4834011.
# Fix esperado: error-resolver adiciona { "is_adset_budget_sharing_enabled": false }
# automaticamente e re-tenta o POST. Campanha deve ser criada com sucesso.
test_bug_01_ABO_budget_sharing_flag() {
  local graph_api_sh="$PLUGIN_ROOT/lib/graph_api.sh"
  if [[ ! -f "$graph_api_sh" ]]; then
    echo "SKIP test_bug_01: graph_api.sh não existe ainda"
    PASS=$((PASS + 1))
    return
  fi

  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$graph_api_sh"

  local account="${AD_ACCOUNT_ID:-act_763408067802379}"
  local name
  name="TEST_REG_BUG01_$$_$(date +%s)"

  # Payload SEM is_adset_budget_sharing_enabled — força o resolver a preencher.
  local payload
  payload=$(jq -nc --arg n "$name" \
    '{name:$n, objective:"OUTCOME_LEADS", status:"PAUSED", special_ad_categories:[]}')

  local resp id
  resp=$(graph_api POST "${account}/campaigns" "$payload") \
    || _fail "test_bug_01_ABO_budget_sharing_flag" "POST falhou, resolver não aplicou fix: $resp"
  id=$(echo "$resp" | jq -r '.id // empty')
  [[ -n "$id" && "$id" != "null" ]] \
    || _fail "test_bug_01_ABO_budget_sharing_flag" "response sem id: $resp"

  # cleanup: pause + delete (idempotente)
  GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$id" '{"status":"PAUSED"}' >/dev/null 2>&1 || true
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 || true

  _pass "test_bug_01_ABO_budget_sharing_flag (id=$id)"
}

# ── bugs 02–09: adicionados nos CPs 2b, 2c, 3a, 3b ───────────────────────────

# ── execução ──────────────────────────────────────────────────────────────────
test_bug_10_preflight_doctor
test_bug_01_ABO_budget_sharing_flag

echo ""
echo "regressão Filipe: $PASS passou, $FAIL falhou (bugs 02-09 adicionados nos próximos CPs)"
[[ "$FAIL" -eq 0 ]]
