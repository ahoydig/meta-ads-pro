#!/usr/bin/env bash
# tests/20-criativo-avancado.sh — Camada 6: criativo avançado (Task 14+).
#
# Testes live contra a conta Meta real. Task 14 cobre só o preview oficial
# via `generatepreviews` (GET puro, sem custo de escrita). T15/T16 acrescentam
# testes que criam adcreatives neste MESMO arquivo — por isso o array
# `created_creatives` + trap de cleanup já existem desde já, mesmo vazios
# nesta task.
#
# Estratégia (Task 14):
#   - test_01: generatepreviews (creative spec inline) retorna iframe pra um
#     ad_format simples (MOBILE_FEED_STANDARD). GET, sem custo de escrita.
#   - test_02: generatepreviews retorna iframe também pra INSTAGRAM_STANDARD
#     (confirma que o endpoint aceita múltiplos ad_format, um por chamada —
#     é isso que preview_meta_oficial faz em loop).
#   - test_03: {creative_id}/previews (creative JÁ existente na conta, lido via
#     GET /adcreatives) também retorna iframe — cobre o outro caminho de
#     preview_meta_oficial (creative_id em vez de spec inline). GET puro,
#     zero custo de escrita, zero criação.
#
# Orçamento de chamadas: 100% GET (generatepreviews + previews + listagem de
# adcreatives). Nenhum POST/DELETE nesta task — o array/trap de cleanup abaixo
# existem só pra servir de base às tasks seguintes (T15/T16) que vão criar
# creatives de verdade neste arquivo.
#
# Bash 3.2 portable. shellcheck clean (disables documentados).

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2" >&2; (( FAIL++ )) || true; exit 1; }
_skip() { echo "- $1 (SKIP: $2)"; (( SKIP++ )) || true; }

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-}"
PAGE_ID="${PAGE_ID:-}"

_need_env() {
  [[ -n "${META_ACCESS_TOKEN:-}" && -n "$AD_ACCOUNT_ID" && -n "$PAGE_ID" ]]
}

# ─── cleanup trap: adcreative (reservado pra T15/T16) ─────────────────────────
# shellcheck disable=SC2034  # populado por tasks futuras que criam creatives
created_creatives=()

# shellcheck disable=SC2329  # invocado via trap
_cleanup_creativo_avancado() {
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh" 2>/dev/null || return 0

  for id in "${created_creatives[@]:-}"; do
    [[ -n "$id" ]] || continue
    echo "→ [cleanup] DELETE adcreative $id"
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 || true
  done
}
trap _cleanup_creativo_avancado EXIT

# ─── Test 01: generatepreviews retorna iframe pra um creative spec mínimo ─────
test_01_generatepreviews() {
  if [[ -z "${META_ACCESS_TOKEN:-}" || -z "${AD_ACCOUNT_ID:-}" || -z "${PAGE_ID:-}" ]]; then
    _skip "test_01_generatepreviews" "sem env"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"
  local spec r
  spec=$(jq -nc --arg pid "$PAGE_ID" \
    '{object_story_spec:{page_id:$pid, link_data:{message:"preview test", link:"https://ahoy.digital"}}}')
  r=$(graph_api GET "${AD_ACCOUNT_ID}/generatepreviews?creative=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$spec")&ad_format=MOBILE_FEED_STANDARD") \
    || _fail "test_01_generatepreviews" "GET falhou: $r"
  echo "$r" | jq -re '.data[0].body' | grep -q "iframe" \
    || _fail "test_01_generatepreviews" "sem iframe no body: $r"
  _pass "test_01_generatepreviews"
}

# ─── Test 02: generatepreviews aceita outro ad_format (INSTAGRAM_STANDARD) ────
# Confirma o segundo formato que preview_meta_oficial itera em loop.
test_02_generatepreviews_instagram_standard() {
  if ! _need_env; then
    _skip "test_02_generatepreviews_instagram_standard" "sem env"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"
  local spec r
  spec=$(jq -nc --arg pid "$PAGE_ID" \
    '{object_story_spec:{page_id:$pid, link_data:{message:"preview test ig", link:"https://ahoy.digital"}}}')
  r=$(graph_api GET "${AD_ACCOUNT_ID}/generatepreviews?creative=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$spec")&ad_format=INSTAGRAM_STANDARD") \
    || _fail "test_02_generatepreviews_instagram_standard" "GET falhou: $r"
  echo "$r" | jq -re '.data[0].body' | grep -q "iframe" \
    || _fail "test_02_generatepreviews_instagram_standard" "sem iframe no body: $r"
  _pass "test_02_generatepreviews_instagram_standard"
}

# ─── Test 03: {creative_id}/previews (creative já existente) retorna iframe ───
# Reaproveita um adcreative já existente na conta (GET puro, zero criação) —
# cobre o caminho "creative_id" de preview_meta_oficial (em vez de spec inline).
test_03_previews_existing_creative_id() {
  if ! _need_env; then
    _skip "test_03_previews_existing_creative_id" "sem env"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"
  local cid r
  cid=$(graph_api GET "${AD_ACCOUNT_ID}/adcreatives?fields=id&limit=1" | jq -r '.data[0].id // empty')
  if [[ -z "$cid" ]]; then
    _skip "test_03_previews_existing_creative_id" "conta sem adcreative existente"
    return 0
  fi
  r=$(graph_api GET "${cid}/previews?ad_format=MOBILE_FEED_STANDARD") \
    || _fail "test_03_previews_existing_creative_id" "GET falhou: $r"
  echo "$r" | jq -re '.data[0].body' | grep -q "iframe" \
    || _fail "test_03_previews_existing_creative_id" "sem iframe no body: $r"
  _pass "test_03_previews_existing_creative_id (cid=$cid)"
}

# ─── Test 04: preview_meta_oficial gera HTML com iframe(s) no disco ───────────
# Exercita a função real de lib/visual-preview.sh de ponta a ponta.
# PREVIEW_NO_OPEN=1 pula o open/xdg-open — suíte roda unattended sem popup.
test_04_preview_meta_oficial_gera_html() {
  if ! _need_env; then
    _skip "test_04_preview_meta_oficial_gera_html" "sem env"; return 0
  fi
  # shellcheck source=../lib/visual-preview.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/visual-preview.sh"
  local spec html_path
  spec=$(jq -nc --arg pid "$PAGE_ID" \
    '{object_story_spec:{page_id:$pid, link_data:{message:"preview_meta_oficial test", link:"https://ahoy.digital"}}}')
  html_path=$(PREVIEW_NO_OPEN=1 preview_meta_oficial "$spec" MOBILE_FEED_STANDARD 2>/dev/null) \
    || _fail "test_04_preview_meta_oficial_gera_html" "função retornou erro"
  [[ -f "$html_path" ]] \
    || _fail "test_04_preview_meta_oficial_gera_html" "arquivo não existe: $html_path"
  grep -q "<iframe" "$html_path" \
    || _fail "test_04_preview_meta_oficial_gera_html" "HTML sem iframe: $html_path"
  _pass "test_04_preview_meta_oficial_gera_html ($html_path)"
}

# ─── Execução ───────────────────────────────────────────────────────────────
# sleep leve entre testes — todos são GET (baratos), mas outro track pode usar
# a mesma conta (ver nota no brief da task).
test_01_generatepreviews
sleep "${CRIATIVO_TEST_READ_SLEEP:-5}"
test_02_generatepreviews_instagram_standard
sleep "${CRIATIVO_TEST_READ_SLEEP:-5}"
test_03_previews_existing_creative_id
sleep "${CRIATIVO_TEST_READ_SLEEP:-5}"
test_04_preview_meta_oficial_gera_html

echo ""
echo "20-criativo-avancado: ${PASS} passou, ${FAIL} falhou, ${SKIP} pulados"
(( FAIL == 0 ))
