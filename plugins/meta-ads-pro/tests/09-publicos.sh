#!/usr/bin/env bash
# tests/09-publicos.sh — CRUD de audiences no skill publicos (CP3, Task 3b.3.6 + Task 18/19)
#
# test_01/02: listagem mínima de custom/saved audiences (apenas GETs).
# test_03:    saved_audiences POST — GUARD-RAIL (Task 18, ver comentário na função).
# test_04:    pixel — criação via API, IDEMPOTENTE (Task 19, ver comentário na função).
#
# Skip gracioso quando META_ACCESS_TOKEN ausente.
# Prefixo TEST_ + cleanup automático via trap (nunca deve ter nada pra limpar
# hoje, já que o POST de saved_audiences é rejeitado — ver test_03 — mas fica
# pronto caso vire escrita real no futuro). Pixel (test_04) NÃO entra nesse
# cleanup — pixel não tem DELETE na Graph API, ver comentário em test_04.
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

# ─── Test 04: Pixel — criação via API, IDEMPOTENTE (Task 19) ────────────────
#
# Diferente de saved_audiences (test_03), a criação de pixel NÃO é bloqueada
# por capability — `POST act_{id}/adspixels` funciona normalmente pra este
# app. Mas pixel não tem DELETE na Graph API, então o design de "cria +
# cleanup no trap" do resto deste arquivo não serve aqui: cada rodada criaria
# um pixel novo e a conta acumularia lixo pra sempre.
#
# Design adotado: no máximo 1 pixel de teste PERMANENTE na conta, com nome
# FIXO (sem timestamp) — TEST_meta-ads-pro_pixel. O teste é idempotente:
#   - Lista os pixels da conta. Se TEST_meta-ads-pro_pixel já existe →
#     valida round-trip (GET {pixel_id}?fields=name,code — o campo `code`
#     precisa vir com o snippet de instalação) e PASSA como "reutilizado".
#     Nenhuma escrita acontece nesse braço.
#   - Se NÃO existe → só cria se RUN_PIXEL_CREATE=1 for setado explicitamente
#     (senão SKIP com instrução — protege contra criação acidental em CI/rodada
#     casual). Cria via POST, valida id + round-trip, PASSA como "criado".
#
# Rodadas futuras (sem a env var, e com o pixel já existindo) sempre caem no
# braço "reutilizado" — zero escrita, teste continua rodando pra sempre sem
# acumular pixels novos.
TEST_PIXEL_NAME="TEST_meta-ads-pro_pixel"

test_04_pixel_lifecycle() {
  local list_r existing_id pixel_id round_trip payload create_r code

  list_r=$(graph_api GET "${AD_ACCOUNT_ID}/adspixels?fields=name,id") \
    || { _fail "test_04_pixel_lifecycle" "graph_api falhou ao listar adspixels"; return; }

  existing_id=$(echo "$list_r" | jq -r --arg n "$TEST_PIXEL_NAME" \
    '.data[]? | select(.name == $n) | .id' | head -n1)

  if [[ -n "$existing_id" ]]; then
    round_trip=$(graph_api GET "${existing_id}?fields=name,code") \
      || { _fail "test_04_pixel_lifecycle" "graph_api falhou no round-trip de ${existing_id}"; return; }
    code=$(echo "$round_trip" | jq -r '.code // empty')
    [[ -n "$code" ]] \
      || { _fail "test_04_pixel_lifecycle" "round-trip sem campo 'code' (snippet de instalação) — resposta: $round_trip"; return; }
    _pass "test_04_pixel_lifecycle (reutilizado — pixel_id=${existing_id}, code presente)"
    return
  fi

  if [[ "${RUN_PIXEL_CREATE:-0}" != "1" ]]; then
    _skip "test_04_pixel_lifecycle" "${TEST_PIXEL_NAME} ainda não existe na conta — rode com RUN_PIXEL_CREATE=1 pra criar (uma vez só; pixel fica permanente, Graph API não tem DELETE pra adspixels)"
    return
  fi

  payload=$(jq -nc --arg n "$TEST_PIXEL_NAME" '{name:$n}')
  create_r=$(graph_api POST "${AD_ACCOUNT_ID}/adspixels" "$payload") \
    || { _fail "test_04_pixel_lifecycle" "graph_api falhou ao criar pixel"; return; }
  pixel_id=$(echo "$create_r" | jq -r '.id // empty')
  [[ -n "$pixel_id" ]] \
    || { _fail "test_04_pixel_lifecycle" "criação não retornou id: $create_r"; return; }

  round_trip=$(graph_api GET "${pixel_id}?fields=name,code") \
    || { _fail "test_04_pixel_lifecycle" "graph_api falhou no round-trip pós-criação de ${pixel_id}"; return; }
  code=$(echo "$round_trip" | jq -r '.code // empty')
  [[ -n "$code" ]] \
    || { _fail "test_04_pixel_lifecycle" "round-trip pós-criação sem campo 'code' — resposta: $round_trip"; return; }
  _pass "test_04_pixel_lifecycle (criado — pixel_id=${pixel_id}, code presente)"
}

test_01_list_custom_audiences
test_02_list_saved_audiences
test_03_saved_audience_create_guardrail
test_04_pixel_lifecycle

echo ""
echo "09-publicos: $PASS passou, $FAIL falhou, $SKIP pulados"
[[ "$FAIL" -eq 0 ]]
