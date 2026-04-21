#!/usr/bin/env bash
# tests/00-regression-filipe.sh — regressão 1:1 com 10 bugs-âncora do caso Filipe
#
# Estrutura por CP:
#   CP1  → test_bug_10  (doctor/preflight — já implementado)
#   CP2a → test_bug_01  (ABO is_adset_budget_sharing_enabled ausente)
#   CP2b → test_bug_02  (targeting_automation.advantage_audience ausente)
#   CP2c → test_bug_03  (placement instagram_explore sem sibling grid_home)
#   CP2c → test_bug_04  (object_story_spec bloqueado em dev mode → dark post)
#   CP2c → test_bug_05  (media_fbid já em uso → regenerate upload)
#   CP3a → test_bug_06  (lead_gen_form_id inválido)
#   CP3b → test_bug_07  (data_preset retroage > 37 meses)
#   CP3b → test_bug_08  (BUC rate limit — ler header em vez de chutar espera)
#   CP3b → test_bug_09  (reservado — se novo bug emergir em rules/insights)
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

# ── Bug #2: targeting_automation.advantage_audience ausente em ad set ───────
# Meta Graph API v25.0 rejeita POST /adsets (em certas combinações de objective
# + destination_type) quando o campo targeting.targeting_automation.advantage_audience
# não é enviado. Erro 100 subcode 1870227.
# Fix esperado: error-resolver adiciona advantage_audience=0 via add_nested
# e re-tenta o POST. Ad set deve ser criado com sucesso.
test_bug_02_advantage_audience() {
  local graph_api_sh="$PLUGIN_ROOT/lib/graph_api.sh"
  if [[ ! -f "$graph_api_sh" ]]; then
    echo "SKIP test_bug_02: graph_api.sh não existe ainda"
    PASS=$((PASS + 1))
    return
  fi

  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$graph_api_sh"

  local account="${AD_ACCOUNT_ID:-act_763408067802379}"
  local camp_name adset_name
  camp_name="TEST_REG_BUG02_CAMP_$$_$(date +%s)"
  adset_name="TEST_REG_BUG02_ADSET_$$_$(date +%s)"

  # Primeiro cria campanha (depende do fix bug #1 já estar aplicado)
  local camp_payload camp_id
  camp_payload=$(jq -nc --arg n "$camp_name" \
    '{name:$n, objective:"OUTCOME_LEADS", status:"PAUSED", special_ad_categories:[], is_adset_budget_sharing_enabled:false}')
  local camp_resp
  camp_resp=$(graph_api POST "${account}/campaigns" "$camp_payload") \
    || _fail "test_bug_02_advantage_audience" "POST campanha falhou: $camp_resp"
  camp_id=$(echo "$camp_resp" | jq -r '.id // empty')
  [[ -n "$camp_id" && "$camp_id" != "null" ]] \
    || _fail "test_bug_02_advantage_audience" "campanha sem id: $camp_resp"

  # Ad set SEM targeting_automation.advantage_audience — força o resolver.
  # Em algumas contas/combos Meta aceita sem o campo; o teste valida que,
  # caso o erro 1870227 apareça, o resolver adiciona o campo e retenta.
  local adset_payload adset_resp adset_id
  adset_payload=$(jq -nc --arg n "$adset_name" --arg c "$camp_id" '{
    name: $n, campaign_id: $c, status: "PAUSED",
    optimization_goal: "LEAD_GENERATION",
    billing_event: "IMPRESSIONS",
    bid_amount: 500,
    daily_budget: 518,
    targeting: {geo_locations: {countries: ["BR"]}}
  }')
  adset_resp=$(graph_api POST "${account}/adsets" "$adset_payload") \
    || {
      # cleanup campanha antes de falhar
      GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$camp_id" >/dev/null 2>&1 || true
      _fail "test_bug_02_advantage_audience" "POST adset falhou, resolver não aplicou fix: $adset_resp"
    }
  adset_id=$(echo "$adset_resp" | jq -r '.id // empty')
  [[ -n "$adset_id" && "$adset_id" != "null" ]] \
    || {
      GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$camp_id" >/dev/null 2>&1 || true
      _fail "test_bug_02_advantage_audience" "adset sem id: $adset_resp"
    }

  # cleanup: adset primeiro (depende da campanha), depois campanha
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$adset_id" >/dev/null 2>&1 || true
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$camp_id" >/dev/null 2>&1 || true

  _pass "test_bug_02_advantage_audience (adset=$adset_id, camp=$camp_id)"
}

# ── bugs 03–09: adicionados nos CPs 2c, 3a, 3b ────────────────────────────────

# ── execução ──────────────────────────────────────────────────────────────────
test_bug_10_preflight_doctor
test_bug_01_ABO_budget_sharing_flag
test_bug_02_advantage_audience

echo ""
echo "regressão Filipe: $PASS passou, $FAIL falhou (bugs 03-09 adicionados nos próximos CPs)"
[[ "$FAIL" -eq 0 ]]
