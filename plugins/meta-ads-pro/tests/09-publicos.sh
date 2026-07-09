#!/usr/bin/env bash
# tests/09-publicos.sh — CRUD de audiences no skill publicos (CP3, Task 3b.3.6 + Task 18)
#
# test_01/02: listagem mínima de custom/saved audiences (apenas GETs).
# test_03:    saved_audiences POST — GUARD-RAIL (Task 18, ver comentário na função).
#
# Skip gracioso quando META_ACCESS_TOKEN ausente.
# Prefixo TEST_ + cleanup automático via trap (nunca deve ter nada pra limpar
# hoje, já que o POST é rejeitado — ver test_03 — mas fica pronto caso vire
# escrita real no futuro).
# Compatível bash 3.2 (macOS).

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "SKIP: sem META_ACCESS_TOKEN — 09-publicos não roda sem token live"
  exit 0
fi

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); }
_skip() { echo "⊘ $1: $2"; SKIP=$((SKIP + 1)); }

# ── cleanup de saved audiences criadas (defensivo — ver test_03) ─────────────
created_saved_audiences=()
_cleanup_saved_audiences() {
  local sid
  for sid in "${created_saved_audiences[@]:-}"; do
    [[ -n "$sid" ]] || continue
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$sid" >/dev/null 2>&1 || true
  done
}
trap _cleanup_saved_audiences EXIT INT TERM

test_01_list_custom_audiences() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/customaudiences?fields=id,name&limit=3") \
    || { _fail "test_01_list_custom_audiences" "graph_api falhou"; return; }
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || { _fail "test_01_list_custom_audiences" "response.data não é array"; return; }
  _pass "test_01_list_custom_audiences"
}

test_02_list_saved_audiences() {
  local r
  r=$(graph_api GET "${AD_ACCOUNT_ID}/saved_audiences?fields=id,name&limit=3") \
    || { _fail "test_02_list_saved_audiences" "graph_api falhou"; return; }
  echo "$r" | jq -e '.data | type == "array"' >/dev/null \
    || { _fail "test_02_list_saved_audiences" "response.data não é array"; return; }
  _pass "test_02_list_saved_audiences"
}

# ─── Test 03: saved_audiences POST — GUARD-RAIL (Task 18) ────────────────────
#
# Reproduzido ao vivo em 2026-07-09 (AD_ACCOUNT_ID desta conta de teste,
# GRAPH_API_SKIP_RESOLVER=1 pra não deixar o error-resolver mascarar o erro):
# o POST em act_{id}/saved_audiences é rejeitado com
#
#   HTTP 400 — OAuthException code 3:
#   "Application does not have the capability to make this API call."
#
# Não é erro de payload (o mesmo shape do brief foi usado) nem de versão
# (v25.0 é a versão mais nova — ver docs/spikes/2026-07-api-version.md, Task 1).
# É um gate de capability/permissão do app na Meta pra esse endpoint
# especificamente — o mesmo app grava normalmente em customaudiences,
# campaigns, adsets e leadgen_forms (ver tests/06 e tests/08), então não é
# um problema de token/escopo geral. Sem app review adicional pra esse
# recurso, escrita fica bloqueada.
#
# Por isso este teste é um GUARD-RAIL, não um teste funcional: PASS quando a
# API rejeita com o erro documentado acima (confirma que o estado real bate
# com o que o SKILL.md descreve — seção 2.6 "somente leitura + criação guiada
# no Ads Manager"). Se um dia a API aceitar (ou rejeitar com erro diferente),
# o teste vira FAIL — sinal pra reavaliar: promover a seção 2.6 a fluxo de
# escrita real (e este teste a round-trip real, como no brief original) ou
# investigar o novo erro.
test_03_saved_audience_create_guardrail() {
  local name payload r sid
  name="TEST_saved_br_25-45_$(date +%s)_$$_$RANDOM"
  payload=$(jq -nc --arg n "$name" '{
    name: $n,
    targeting: {
      geo_locations: {countries: ["BR"]},
      age_min: 25,
      age_max: 45,
      targeting_automation: {advantage_audience: 0}
    }
  }')

  if r=$(GRAPH_API_SKIP_RESOLVER=1 graph_api POST "${AD_ACCOUNT_ID}/saved_audiences" "$payload" 2>&1); then
    # POST aceito — guard-rail estourou, isso é uma FALHA do guard-rail (sinal
    # de que a API mudou de comportamento), não um sucesso silencioso.
    sid=$(echo "$r" | jq -r '.id // empty' 2>/dev/null || true)
    [[ -n "$sid" ]] && created_saved_audiences+=("$sid")
    _fail "test_03_saved_audience_create_guardrail" \
      "saved_audiences ACEITOU escrita (sid=${sid:-desconhecido}) — guard-rail estourou. Atualizar SKILL.md seção 2.6 (promover de 'somente leitura' pra fluxo de criação real) e este teste (pra round-trip real, ver brief da Task 18): $r"
    return
  fi

  if echo "$r" | jq -e '.error.code == 3' >/dev/null 2>&1; then
    _pass "test_03_saved_audience_create_guardrail (rejeitado como esperado — OAuthException code 3 'Application does not have the capability to make this API call')"
  else
    _fail "test_03_saved_audience_create_guardrail" \
      "rejeitado, mas com erro diferente do documentado (esperava .error.code == 3) — reavaliar guard-rail: $r"
  fi
}

test_01_list_custom_audiences
test_02_list_saved_audiences
test_03_saved_audience_create_guardrail

echo ""
echo "09-publicos: $PASS passou, $FAIL falhou, $SKIP pulados"
[[ "$FAIL" -eq 0 ]]
