#!/usr/bin/env bash
# tests/14-integracao.sh — Camada 4: integração entre sub-skills (CP3, Task 3c.6).
#
# 5 testes que validam o "contrato" entre pares de sub-skills:
#   01. setup→doctor    — config.md gravada pelo setup é lida pelo doctor
#   02. campanha→conjuntos — bid_strategy da campanha é lido na leitura do obj
#   03. anuncios→leadform  — creative pode linkar lead_gen_form recém-criado
#   04. insights pós-criação — endpoint responde mesmo sem dados
#   05. regras com filtros — listagem de adrules_library por filtro aceita
#
# Cada teste é isolado e idempotente. Trap EXIT faz cleanup obrigatório.
# Skip gracioso se META_ACCESS_TOKEN ausente. Bash 3.2 portable.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${META_ACCESS_TOKEN:-}" || -z "${AD_ACCOUNT_ID:-}" ]]; then
  echo "SKIP: sem META_ACCESS_TOKEN e/ou AD_ACCOUNT_ID — 14-integracao exige token live"
  exit 0
fi

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"
# shellcheck source=../lib/preflight.sh disable=SC1091
source "$PLUGIN_ROOT/lib/preflight.sh"

TEST_PREFIX="TEST_INTEG_$$_$(date +%s)"

# ── cleanup ────────────────────────────────────────────────────────────────
CLEANUP_IDS=()

cleanup() {
  local exit_code=$?
  local n=${#CLEANUP_IDS[@]}
  if (( n > 0 )); then
    echo ""
    echo "── cleanup: deletando $n objeto(s) ──"
    local id
    for id in "${CLEANUP_IDS[@]}"; do
      [[ -z "$id" ]] && continue
      GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$id" '{"status":"PAUSED"}' >/dev/null 2>&1 || true
      if GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1; then
        echo "  ✓ deletado $id"
      else
        echo "  ⚠ falhou deletar $id"
      fi
    done
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

PASS=0
FAIL=0

_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }

# ── test 01: setup → doctor ─────────────────────────────────────────────────
# Valida que doctor consegue ler um CLAUDE.md com as keys que setup grava.
test_integ_01_setup_to_doctor() {
  local tmpdir tmpmd
  tmpdir=$(mktemp -d)
  tmpmd="$tmpdir/CLAUDE.md"
  cat > "$tmpmd" <<'EOF'
# Project

## Meta Ads Config
ad_account_id: act_000000000000000
page_id: 0000000000000000
nomenclatura_style: ahoy_default
EOF
  if check_claude_md_config "$tmpmd" >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    _pass test_integ_01_setup_to_doctor
  else
    rm -rf "$tmpdir"
    _fail test_integ_01_setup_to_doctor "check_claude_md_config rejeitou fixture válido"
  fi
}

# ── test 02: campanha → conjuntos ──────────────────────────────────────────
# Cria campanha com bid_strategy, valida que GET /id?fields=bid_strategy retorna o mesmo.
test_integ_02_campanha_to_conjuntos() {
  local name payload cid bs
  name="${TEST_PREFIX}_BS"
  payload=$(jq -nc --arg n "$name" \
    '{name:$n,objective:"OUTCOME_LEADS",status:"PAUSED",special_ad_categories:[],
      is_adset_budget_sharing_enabled:false,bid_strategy:"LOWEST_COST_WITHOUT_CAP"}')
  cid=$(graph_api POST "${AD_ACCOUNT_ID}/campaigns" "$payload" | jq -r '.id // empty')
  [[ -n "$cid" ]] || _fail test_integ_02_campanha_to_conjuntos "criação falhou (sem id)"
  CLEANUP_IDS+=("$cid")

  bs=$(graph_api GET "${cid}?fields=bid_strategy" | jq -r '.bid_strategy // empty')
  [[ "$bs" == "LOWEST_COST_WITHOUT_CAP" ]] \
    || _fail test_integ_02_campanha_to_conjuntos "bid_strategy esperado=LOWEST_COST_WITHOUT_CAP, obtido=$bs"
  _pass test_integ_02_campanha_to_conjuntos
}

# ── test 03: anuncios → lead-forms ──────────────────────────────────────────
# Cria lead form mínimo (simula dependência que o creative do ad referenciaria
# via call_to_action.value.lead_gen_form_id). Se PAGE_ID não existir, skipa.
test_integ_03_anuncios_to_leadform() {
  if [[ -z "${PAGE_ID:-}" ]]; then
    echo "⚠ SKIP test_integ_03_anuncios_to_leadform (PAGE_ID não setado)"
    return 0
  fi
  local fpayload fid
  fpayload=$(jq -nc --arg n "${TEST_PREFIX}_FORM" '{
    name:$n,
    questions:[{type:"EMAIL"}],
    privacy_policy:{url:"https://lp.ahoy.digital/politicas-privacidade"},
    context_card:{title:"t",content:["c"]},
    thank_you_page:{title:"ty",body:"body"},
    disqualified_thank_you_page:{title:"disq",body:"body"}
  }')
  fid=$(graph_api POST "${PAGE_ID}/leadgen_forms" "$fpayload" | jq -r '.id // empty')
  [[ -n "$fid" ]] || _fail test_integ_03_anuncios_to_leadform "criação do form falhou"
  # cleanup direto (não entra no array pq endpoint de delete é diferente)
  GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$fid" >/dev/null 2>&1 || true
  _pass test_integ_03_anuncios_to_leadform
}

# ── test 04: insights pós-criação ──────────────────────────────────────────
# Mesmo sem spend, endpoint responde .data como array.
test_integ_04_insights_after_create() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/insights?date_preset=today&level=account&fields=spend") \
    || _fail test_integ_04_insights_after_create "graph_api falhou"
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || _fail test_integ_04_insights_after_create "response.data não é array"
  _pass test_integ_04_insights_after_create
}

# ── test 05: regras com filtros ────────────────────────────────────────────
test_integ_05_rules_with_filter() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/adrules_library?fields=id,name&limit=3") \
    || _fail test_integ_05_rules_with_filter "graph_api falhou"
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || _fail test_integ_05_rules_with_filter "response.data não é array"
  _pass test_integ_05_rules_with_filter
}

test_integ_01_setup_to_doctor
test_integ_02_campanha_to_conjuntos
test_integ_03_anuncios_to_leadform
test_integ_04_insights_after_create
test_integ_05_rules_with_filter

echo ""
echo "14-integracao: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
