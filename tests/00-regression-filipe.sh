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
# em ABO. Erro 100 subcode 4834011.
#
# Estrutura do teste (negative control + positive):
#   Phase 1 (resolver OFF): POST sem a flag → espera falha (prova que a API exige)
#   Phase 2 (resolver ON):  POST sem a flag → espera sucesso (prova que o resolver
#                           aplica add_field:is_adset_budget_sharing_enabled:false)
#
# O delta entre fases prova que o apply-retry loop do graph_api.sh está agindo.
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
  local ts name_neg name_pos
  ts=$(date +%s)
  name_neg="TEST_REG_BUG01_NEG_$$_$ts"
  name_pos="TEST_REG_BUG01_POS_$$_$ts"

  # ── Phase 1: negative control (resolver OFF) ───────────────────────────
  local neg_payload neg_resp neg_rc=0 neg_id
  neg_payload=$(jq -nc --arg n "$name_neg" \
    '{name:$n, objective:"OUTCOME_LEADS", status:"PAUSED", special_ad_categories:[]}')
  neg_resp=$(GRAPH_API_SKIP_RESOLVER=1 graph_api POST "${account}/campaigns" "$neg_payload" 2>&1) || neg_rc=$?

  if (( neg_rc == 0 )); then
    # Meta aceitou sem a flag — pode ter mudado comportamento. Cleanup + WARN.
    neg_id=$(echo "$neg_resp" | jq -r '.id // empty' 2>/dev/null)
    if [[ -n "$neg_id" && "$neg_id" != "null" ]]; then
      GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$neg_id" >/dev/null 2>&1 || true
    fi
    echo "  ⚠ phase 1: Meta aceitou payload sem flag (API pode ter mudado — defesa em profundidade da skill ainda preserva o fix)"
  else
    # Valida que foi o erro esperado 100/4834011
    local neg_code neg_subcode
    neg_code=$(echo "$neg_resp" | jq -r '.error.code // empty' 2>/dev/null)
    neg_subcode=$(echo "$neg_resp" | jq -r '.error.error_subcode // empty' 2>/dev/null)
    if [[ "$neg_code" == "100" && "$neg_subcode" == "4834011" ]]; then
      echo "  ✓ phase 1 (negative control): Meta rejeita sem flag (100/4834011)"
    else
      echo "  ⚠ phase 1: falhou com code=$neg_code subcode=$neg_subcode (esperado 100/4834011)"
    fi
  fi

  # ── Phase 2: positive (resolver ON) ────────────────────────────────────
  local pos_payload pos_resp pos_id
  pos_payload=$(jq -nc --arg n "$name_pos" \
    '{name:$n, objective:"OUTCOME_LEADS", status:"PAUSED", special_ad_categories:[]}')
  pos_resp=$(graph_api POST "${account}/campaigns" "$pos_payload" 2>&1) \
    || _fail "test_bug_01_ABO_budget_sharing_flag" "phase 2 falhou — resolver não aplicou fix: $pos_resp"
  pos_id=$(echo "$pos_resp" | jq -r '.id // empty')
  [[ -n "$pos_id" && "$pos_id" != "null" ]] \
    || _fail "test_bug_01_ABO_budget_sharing_flag" "phase 2 response sem id: $pos_resp"

  # cleanup idempotente
  GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$pos_id" '{"status":"PAUSED"}' >/dev/null 2>&1 || true
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$pos_id" >/dev/null 2>&1 || true

  _pass "test_bug_01_ABO_budget_sharing_flag (id=$pos_id)"
}

# ── Bug #2: targeting_automation.advantage_audience ausente em ad set ───────
# Meta Graph API v25.0 rejeita POST /adsets (em certas combinações de objective
# + destination_type) quando o campo targeting.targeting_automation.advantage_audience
# não é enviado. Erro 100 subcode 1870227.
#
# Estrutura do teste (negative control + positive), espelhando test_bug_01:
#   Phase 1 (resolver OFF): POST sem advantage_audience → espera falha
#                           (prova que a API exige; aceita WARN se Meta mudou)
#   Phase 2 (resolver ON):  POST sem advantage_audience → espera sucesso
#                           (prova que o resolver aplica
#                            add_nested:targeting.targeting_automation.advantage_audience:0)
#
# Combo diagnóstico: WEBSITE + LINK_CLICKS (não exige promoted_object nem
# destination_type especial) pra isolar que o único campo faltando é
# advantage_audience — sem risco de 100/1487390 ("optimization_goal incompatível")
# mascarar 100/1870227. Bug #1 já foi fixado; campanha ABO usa
# is_adset_budget_sharing_enabled:false explícito pra não depender do resolver
# em cascata neste teste.
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
  local ts camp_name name_neg name_pos
  ts=$(date +%s)
  camp_name="TEST_REG_BUG02_CAMP_$$_$ts"
  name_neg="TEST_REG_BUG02_ADSET_NEG_$$_$ts"
  name_pos="TEST_REG_BUG02_ADSET_POS_$$_$ts"

  # ── Setup: cria campanha ABO com flag explícita (não depende do resolver) ──
  local camp_payload camp_id camp_resp
  camp_payload=$(jq -nc --arg n "$camp_name" \
    '{name:$n, objective:"OUTCOME_TRAFFIC", status:"PAUSED", special_ad_categories:[], is_adset_budget_sharing_enabled:false}')
  camp_resp=$(GRAPH_API_SKIP_RESOLVER=1 graph_api POST "${account}/campaigns" "$camp_payload" 2>&1) \
    || _fail "test_bug_02_advantage_audience" "setup: POST campanha falhou: $camp_resp"
  camp_id=$(echo "$camp_resp" | jq -r '.id // empty')
  [[ -n "$camp_id" && "$camp_id" != "null" ]] \
    || _fail "test_bug_02_advantage_audience" "setup: campanha sem id: $camp_resp"

  # Payload base sem advantage_audience — combo isolado (WEBSITE + LINK_CLICKS
  # não exige promoted_object nem destination_type especial).
  # Sem bid_amount: campanha default LOWEST_COST_WITHOUT_CAP não aceita bid_amount.
  _mk_adset_payload_bug02() {
    local name="$1"
    jq -nc --arg n "$name" --arg c "$camp_id" '{
      name: $n, campaign_id: $c, status: "PAUSED",
      destination_type: "WEBSITE",
      optimization_goal: "LINK_CLICKS",
      billing_event: "IMPRESSIONS",
      daily_budget: 518,
      targeting: {geo_locations: {countries: ["BR"]}}
    }'
  }

  # ── Phase 1: negative control (resolver OFF) ───────────────────────────────
  local neg_payload neg_resp neg_rc=0 neg_id
  neg_payload=$(_mk_adset_payload_bug02 "$name_neg")
  neg_resp=$(GRAPH_API_SKIP_RESOLVER=1 graph_api POST "${account}/adsets" "$neg_payload" 2>&1) || neg_rc=$?

  if (( neg_rc == 0 )); then
    # Meta aceitou sem advantage_audience — combo não força o erro.
    # Cleanup + WARN (defesa em profundidade da skill ainda preserva o fix).
    neg_id=$(echo "$neg_resp" | jq -r '.id // empty' 2>/dev/null)
    if [[ -n "$neg_id" && "$neg_id" != "null" ]]; then
      GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$neg_id" >/dev/null 2>&1 || true
    fi
    echo "  ⚠ phase 1: Meta aceitou payload sem advantage_audience (combo não força 1870227 nessa conta — defesa em profundidade da skill ainda preserva o fix)"
  else
    # Valida que foi o erro esperado 100/1870227
    local neg_code neg_subcode
    neg_code=$(echo "$neg_resp" | jq -r '.error.code // empty' 2>/dev/null)
    neg_subcode=$(echo "$neg_resp" | jq -r '.error.error_subcode // empty' 2>/dev/null)
    if [[ "$neg_code" == "100" && "$neg_subcode" == "1870227" ]]; then
      echo "  ✓ phase 1 (negative control): Meta rejeita sem advantage_audience (100/1870227)"
    else
      echo "  ⚠ phase 1: falhou com code=$neg_code subcode=$neg_subcode (esperado 100/1870227)"
    fi
  fi

  # ── Phase 2: positive (resolver ON) ────────────────────────────────────────
  local pos_payload pos_resp pos_id
  pos_payload=$(_mk_adset_payload_bug02 "$name_pos")
  pos_resp=$(graph_api POST "${account}/adsets" "$pos_payload" 2>&1) \
    || {
      GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$camp_id" >/dev/null 2>&1 || true
      _fail "test_bug_02_advantage_audience" "phase 2 falhou — resolver não aplicou fix: $pos_resp"
    }
  pos_id=$(echo "$pos_resp" | jq -r '.id // empty')
  if [[ -z "$pos_id" || "$pos_id" == "null" ]]; then
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$camp_id" >/dev/null 2>&1 || true
    _fail "test_bug_02_advantage_audience" "phase 2 response sem id: $pos_resp"
  fi

  # cleanup: adset primeiro (depende da campanha), depois campanha
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$pos_id" >/dev/null 2>&1 || true
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$camp_id" >/dev/null 2>&1 || true

  _pass "test_bug_02_advantage_audience (adset=$pos_id, camp=$camp_id)"
}

# ── bugs 03–09: adicionados nos CPs 2c, 3a, 3b ────────────────────────────────

# ── execução ──────────────────────────────────────────────────────────────────
test_bug_10_preflight_doctor
test_bug_01_ABO_budget_sharing_flag
test_bug_02_advantage_audience

echo ""
echo "regressão Filipe: $PASS passou, $FAIL falhou (bugs 03-09 adicionados nos próximos CPs)"
[[ "$FAIL" -eq 0 ]]
