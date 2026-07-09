#!/usr/bin/env bash
# tests/05-campanha-crud.sh — CRUD end-to-end de campanhas (CP2a)
#
# 12 testes contra a conta do Flávio (AD_ACCOUNT_ID env ou act_763408067802379).
# Cada teste: cria TEST_CRUD_*, valida payload/response, registra ID pra cleanup.
# Trap EXIT garante rollback mesmo em falha intermediária.
#
# Skip gracioso se META_ACCESS_TOKEN não estiver setado.
# Bash 3.2 portable (sem mapfile, declare -A, GNU sed).

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── skip gracioso ──────────────────────────────────────────────────────────
if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "SKIP: sem META_ACCESS_TOKEN — 05-campanha-crud não roda sem token live"
  exit 0
fi

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"
TEST_PREFIX="TEST_CRUD_$$_$(date +%s)"
MIN_BUDGET_CENTS=1000  # R$10,00 — folga acima do min_daily_budget=522 do Flávio

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

# ── cleanup trap ──────────────────────────────────────────────────────────
CLEANUP_IDS=()

cleanup() {
  local exit_code=$?
  local n=${#CLEANUP_IDS[@]}
  if (( n > 0 )); then
    echo ""
    echo "── cleanup: deletando $n objeto(s) criado(s) ──"
    local id
    for id in "${CLEANUP_IDS[@]}"; do
      [[ -z "$id" ]] && continue
      # pausa antes de deletar (Meta bloqueia DELETE em ACTIVE)
      GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$id" '{"status":"PAUSED"}' >/dev/null 2>&1 || true
      if GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1; then
        echo "  ✓ deletado $id"
      else
        echo "  ⚠ falhou deletar $id (pode já ter sido removido)"
      fi
    done
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ── helpers ──────────────────────────────────────────────────────────────
PASS=0
FAIL=0

_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }

# Constrói payload base ABO (sem daily_budget)
# args: name objective bid_strategy (3º arg mantido por compat de call sites,
# mas NÃO vai no payload — ver nota abaixo)
#
# bid_strategy NÃO entra no payload da campanha em ABO (achado ao vivo T22):
# a conta passou a rejeitar bid_strategy no nível da campanha quando ela não
# tem daily_budget próprio — erro 100/1885737 "Esta campanha não tem
# orçamento. Adicione um orçamento para editar a estratégia de lance."
# Mesma regra geral do bid_strategy-precisa-acompanhar-o-orçamento já
# encontrada no lado do ad set (100/2490487, tests/06 + flows/conjuntos):
# em ABO, quem tem budget é o ad set — é lá que bid_strategy deve viver, não
# na campanha (que fica sem daily_budget por design do ABO).
_payload_abo() {
  jq -nc \
    --arg n "$1" \
    --arg o "$2" \
    '{name:$n, objective:$o, status:"PAUSED", special_ad_categories:[],
      is_adset_budget_sharing_enabled:false}'
}

# Constrói payload CBO (com daily_budget em centavos)
# args: name objective bid_strategy daily_budget_cents
_payload_cbo() {
  jq -nc \
    --arg n "$1" \
    --arg o "$2" \
    --arg b "$3" \
    --argjson d "$4" \
    '{name:$n, objective:$o, status:"PAUSED", special_ad_categories:[],
      is_adset_budget_sharing_enabled:false, bid_strategy:$b, daily_budget:$d}'
}

# POST + retorna id. Aborta teste se falhar.
# args: name payload test_name
#
# NOTA (leak de órfãos, mesmo achado do mk_campaign em tests/06 — T22):
# esta função roda dentro do subshell de `id=$(_create_campaign ...)` no
# caller. Um `CLEANUP_IDS+=(...)` FEITO AQUI DENTRO só existe na cópia do
# array do subshell e some quando ele termina (bash 3.2, sem shared memory
# entre subshells) — o CLEANUP_IDS do script principal nunca recebia os ids,
# e ficava permanentemente vazio. Dois efeitos: (a) toda campanha criada por
# este arquivo vazava (o trap de cleanup nunca via nada pra apagar); (b) sob
# `set -u`, um array bash 3.2 com ZERO elementos dá "unbound variable" na
# primeira vez que alguém faz `"${CLEANUP_IDS[@]}"` sem guarda (reproduzido
# ao vivo: crashava em test_camp_delete_paused, a 1ª expansão direta do
# array no arquivo). Fix: só ecoa o id; cada CALL SITE abaixo faz
# `CLEANUP_IDS+=("$id")` no shell principal, fora do subshell.
_create_campaign() {
  local payload="$1"
  local test_name="$2"
  local resp id
  resp=$(graph_api POST "${AD_ACCOUNT_ID}/campaigns" "$payload") \
    || _fail "$test_name" "POST falhou: $resp"
  id=$(echo "$resp" | jq -r '.id // empty')
  [[ -n "$id" ]] || _fail "$test_name" "response sem id: $resp"
  echo "$id"
}

# Guarda de DELETE: espelha o contrato da skill (só deleta PAUSED)
# args: campaign_id
_campanha_delete_guarded() {
  local id="$1"
  local status
  status=$(graph_api GET "${id}?fields=status" | jq -r '.status // empty')
  if [[ "$status" == "ACTIVE" ]]; then
    echo "BLOCKED_ACTIVE" >&2
    return 2
  fi
  graph_api DELETE "$id"
}

# ── TESTES ────────────────────────────────────────────────────────────────

# #1 — OUTCOME_LEADS ABO: valida flag is_adset_budget_sharing_enabled=false
test_camp_create_outcome_leads_abo() {
  local name="${TEST_PREFIX}_LEADS_ABO"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_LEADS" "LOWEST_COST_WITHOUT_CAP")

  # assertion do payload (fix bug #1)
  local flag
  flag=$(echo "$payload" | jq -r '.is_adset_budget_sharing_enabled')
  [[ "$flag" == "false" ]] \
    || _fail "test_camp_create_outcome_leads_abo" "flag is_adset_budget_sharing_enabled='$flag' (esperado false)"

  # ABO não deve ter daily_budget
  local has_budget
  has_budget=$(echo "$payload" | jq 'has("daily_budget")')
  [[ "$has_budget" == "false" ]] \
    || _fail "test_camp_create_outcome_leads_abo" "ABO não pode ter daily_budget no payload"

  local id
  id=$(_create_campaign "$payload" "test_camp_create_outcome_leads_abo")
  CLEANUP_IDS+=("$id")
  _pass "test_camp_create_outcome_leads_abo (id=$id)"
}

# #2 — OUTCOME_SALES CBO: valida que payload tem daily_budget
test_camp_create_outcome_sales_cbo() {
  local name="${TEST_PREFIX}_SALES_CBO"
  local payload
  payload=$(_payload_cbo "$name" "OUTCOME_SALES" "LOWEST_COST_WITHOUT_CAP" "$MIN_BUDGET_CENTS")

  local budget
  budget=$(echo "$payload" | jq -r '.daily_budget')
  [[ "$budget" == "$MIN_BUDGET_CENTS" ]] \
    || _fail "test_camp_create_outcome_sales_cbo" "daily_budget='$budget' esperado $MIN_BUDGET_CENTS"

  local id
  id=$(_create_campaign "$payload" "test_camp_create_outcome_sales_cbo")
  CLEANUP_IDS+=("$id")
  _pass "test_camp_create_outcome_sales_cbo (id=$id)"
}

# #3 — OUTCOME_TRAFFIC ABO
test_camp_create_outcome_traffic() {
  local name="${TEST_PREFIX}_TRAFFIC"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_TRAFFIC" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_create_outcome_traffic")
  CLEANUP_IDS+=("$id")
  _pass "test_camp_create_outcome_traffic (id=$id)"
}

# #4 — OUTCOME_ENGAGEMENT ABO
test_camp_create_outcome_engagement() {
  local name="${TEST_PREFIX}_ENGAGEMENT"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_ENGAGEMENT" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_create_outcome_engagement")
  CLEANUP_IDS+=("$id")
  _pass "test_camp_create_outcome_engagement (id=$id)"
}

# #5 — OUTCOME_AWARENESS ABO
test_camp_create_outcome_awareness() {
  local name="${TEST_PREFIX}_AWARENESS"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_AWARENESS" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_create_outcome_awareness")
  CLEANUP_IDS+=("$id")
  _pass "test_camp_create_outcome_awareness (id=$id)"
}

# #6 — list campaigns (filtro active) deve retornar array
test_camp_list_active() {
  local resp
  resp=$(graph_api GET "${AD_ACCOUNT_ID}/campaigns?fields=id,name,status&limit=5") \
    || _fail "test_camp_list_active" "GET falhou: $resp"
  local ok
  ok=$(echo "$resp" | jq -r 'if .data then "yes" else "no" end')
  [[ "$ok" == "yes" ]] \
    || _fail "test_camp_list_active" "response sem .data: $resp"
  _pass "test_camp_list_active"
}

# #7 — pause: cria PAUSED, ativa, pausa, verifica
test_camp_pause() {
  local name="${TEST_PREFIX}_PAUSE"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_TRAFFIC" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_pause")
  CLEANUP_IDS+=("$id")

  graph_api POST "$id" '{"status":"ACTIVE"}' >/dev/null \
    || _fail "test_camp_pause" "activate falhou"
  graph_api POST "$id" '{"status":"PAUSED"}' >/dev/null \
    || _fail "test_camp_pause" "pause falhou"

  local status
  status=$(graph_api GET "${id}?fields=status" | jq -r '.status')
  [[ "$status" == "PAUSED" ]] \
    || _fail "test_camp_pause" "status='$status' esperado PAUSED"
  _pass "test_camp_pause (id=$id)"
}

# #8 — activate: cria PAUSED, ativa, verifica
test_camp_activate() {
  local name="${TEST_PREFIX}_ACTIVATE"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_TRAFFIC" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_activate")
  CLEANUP_IDS+=("$id")

  graph_api POST "$id" '{"status":"ACTIVE"}' >/dev/null \
    || _fail "test_camp_activate" "activate falhou"

  local status
  status=$(graph_api GET "${id}?fields=status" | jq -r '.status')
  [[ "$status" == "ACTIVE" ]] \
    || _fail "test_camp_activate" "status='$status' esperado ACTIVE"
  _pass "test_camp_activate (id=$id)"
}

# #9 — edit budget: cria CBO, altera daily_budget, verifica
test_camp_edit_budget() {
  local name="${TEST_PREFIX}_EDIT"
  local new_budget=$((MIN_BUDGET_CENTS * 2))
  local payload
  payload=$(_payload_cbo "$name" "OUTCOME_SALES" "LOWEST_COST_WITHOUT_CAP" "$MIN_BUDGET_CENTS")
  local id
  id=$(_create_campaign "$payload" "test_camp_edit_budget")
  CLEANUP_IDS+=("$id")

  local edit_payload
  edit_payload=$(jq -nc --argjson d "$new_budget" '{daily_budget:$d}')
  graph_api POST "$id" "$edit_payload" >/dev/null \
    || _fail "test_camp_edit_budget" "edit falhou"

  local current
  current=$(graph_api GET "${id}?fields=daily_budget" | jq -r '.daily_budget')
  [[ "$current" == "$new_budget" ]] \
    || _fail "test_camp_edit_budget" "daily_budget='$current' esperado $new_budget"
  _pass "test_camp_edit_budget (id=$id)"
}

# #10 — delete PAUSED funciona
test_camp_delete_paused() {
  local name="${TEST_PREFIX}_DEL_PAUSED"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_TRAFFIC" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_delete_paused")
  CLEANUP_IDS+=("$id")

  _campanha_delete_guarded "$id" >/dev/null 2>&1 \
    || _fail "test_camp_delete_paused" "delete guarded falhou pra campanha PAUSED"

  # Remove da cleanup list (já deletada). Expansão guardada com
  # "${CLEANUP_IDS[@]+...}" (mesmo idiom já usado abaixo pra $new):
  # bash 3.2 dá "unbound variable" em "${arr[@]}" sob `set -u` quando o
  # array tem ZERO elementos — achado ao vivo nesta função (T22).
  local i new=()
  for i in "${CLEANUP_IDS[@]+${CLEANUP_IDS[@]}}"; do
    [[ "$i" != "$id" ]] && new+=("$i")
  done
  CLEANUP_IDS=("${new[@]+${new[@]}}")

  _pass "test_camp_delete_paused (id=$id)"
}

# #11 — delete ACTIVE bloqueado pelo guard
test_camp_delete_active_blocked() {
  local name="${TEST_PREFIX}_DEL_ACTIVE"
  local payload
  payload=$(_payload_abo "$name" "OUTCOME_TRAFFIC" "LOWEST_COST_WITHOUT_CAP")
  local id
  id=$(_create_campaign "$payload" "test_camp_delete_active_blocked")
  CLEANUP_IDS+=("$id")

  graph_api POST "$id" '{"status":"ACTIVE"}' >/dev/null \
    || _fail "test_camp_delete_active_blocked" "activate falhou"

  local rc=0
  _campanha_delete_guarded "$id" >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "2" ]] \
    || _fail "test_camp_delete_active_blocked" "guard retornou '$rc' esperado 2 (BLOCKED_ACTIVE)"

  # cleanup normal vai pausar+deletar depois
  _pass "test_camp_delete_active_blocked (id=$id)"
}

# #12 — bid_strategy LOWEST_COST_WITH_MIN_ROAS (com bid_amount obrigatório)
test_camp_bid_strategy_min_roas() {
  local name="${TEST_PREFIX}_MIN_ROAS"
  # MIN_ROAS exige bid_amount (basis points = ROAS * 10000; ex: 2.0 = 20000)
  local payload
  payload=$(jq -nc \
    --arg n "$name" \
    --argjson d "$MIN_BUDGET_CENTS" \
    '{name:$n, objective:"OUTCOME_SALES", status:"PAUSED", special_ad_categories:[],
      is_adset_budget_sharing_enabled:false,
      bid_strategy:"LOWEST_COST_WITH_MIN_ROAS",
      bid_amount: 20000,
      daily_budget:$d}')

  local id
  id=$(_create_campaign "$payload" "test_camp_bid_strategy_min_roas")
  CLEANUP_IDS+=("$id")

  local strategy
  strategy=$(graph_api GET "${id}?fields=bid_strategy" | jq -r '.bid_strategy')
  [[ "$strategy" == "LOWEST_COST_WITH_MIN_ROAS" ]] \
    || _fail "test_camp_bid_strategy_min_roas" "bid_strategy='$strategy' esperado LOWEST_COST_WITH_MIN_ROAS"
  _pass "test_camp_bid_strategy_min_roas (id=$id)"
}

# ── runner ────────────────────────────────────────────────────────────────
echo "━━━ 05-campanha-crud (conta: $AD_ACCOUNT_ID, prefixo: $TEST_PREFIX) ━━━"

test_camp_create_outcome_leads_abo
test_camp_create_outcome_sales_cbo
test_camp_create_outcome_traffic
test_camp_create_outcome_engagement
test_camp_create_outcome_awareness
test_camp_list_active
test_camp_pause
test_camp_activate
test_camp_edit_budget
test_camp_delete_paused
test_camp_delete_active_blocked
test_camp_bid_strategy_min_roas

echo ""
echo "Results: $PASS passou, $FAIL falhou"
(( FAIL == 0 ))
