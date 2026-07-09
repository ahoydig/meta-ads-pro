#!/usr/bin/env bash
# tests/18-boost-ig.sh — Camada 6: sub-skill boost (Task 13, /meta-ads-boost).
#
# Testes live contra a conta Meta real (act_763408067802379 / IG 17841436814014233).
# Payloads ancorados em docs/spikes/2026-07-boost-ig.md (autoritativo sobre o brief
# original — o creative de boost NÃO leva object_story_spec).
#
# Estratégia:
#   - test_01: listagem de mídia (GET, sem custo de escrita)
#   - test_02: creative com o payload CORRETO ({name, source_instagram_media_id}
#     sozinho) — 1 POST. Guarda o creative_id pra reaproveitar no test_06 (evita
#     criar um segundo creative só pra testar a cadeia completa).
#   - test_03: guarda de regressão — o payload do brief original
#     (object_story_spec{page_id,instagram_user_id} + source_instagram_media_id)
#     TEM que continuar falhando. Se um dia passar a funcionar, o spike/SKILL.md
#     ficaram desatualizados — investigar antes de "corrigir" este teste.
#   - test_04: boost_eligibility_info existe no schema (GET, sem custo de escrita)
#   - test_05: reel conhecido do spike como ineligível por música (best-effort —
#     GET, sem custo de escrita; skip gracioso se o post não existir mais ou a
#     conta tiver mudado desde o spike)
#   - test_06: cadeia completa campanha→adset(ON_POST/POST_ENGAGEMENT/bid_strategy
#     obrigatório)→ad, reaproveitando o creative do test_02. Confirma via preview
#     que o ad referencia o post orgânico.
#
# Orçamento de chamadas de escrita: test_02 (1) + test_03 (1, falha esperada) +
# test_06 (3: campanha/adset/ad) = 5 POSTs + até 4 DELETEs no cleanup = 9 total.
# Sleep de 15-20s entre escritas (outro track pode estar batendo na mesma conta —
# ver nota no brief). Se aparecer erro código 17 (rate limit), pare, espere uns
# 5 minutos e rode de novo — este script não tenta retry automático de propósito
# (evita mascarar rate limit real durante desenvolvimento).
#
# Cleanup: ad → adcreative → adset → campaign (mesma topologia de lib/rollback.sh).
# Prefixo TEST_ garante cleanup via tests/cleanup.sh caso o trap falhe.
#
# Bash 3.2 portable. shellcheck clean (disables documentados).

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2" >&2; (( FAIL++ )) || true; exit 1; }
_skip() { echo "- $1 (SKIP: $2)"; (( SKIP++ )) || true; }

# sleep entre chamadas de escrita — outro track pode estar na mesma conta.
_sleep_write() { sleep "${BOOST_TEST_WRITE_SLEEP:-18}"; }

AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-}"
PAGE_ID="${PAGE_ID:-}"
INSTAGRAM_USER_ID="${INSTAGRAM_USER_ID:-}"

_need_env() {
  [[ -n "${META_ACCESS_TOKEN:-}" && -n "$AD_ACCOUNT_ID" && -n "$PAGE_ID" && -n "$INSTAGRAM_USER_ID" ]]
}

# ─── cleanup trap: ad → adcreative → adset → campaign ─────────────────────────
created_ads=()
created_creatives=()
created_adsets=()
created_campaigns=()

# shellcheck disable=SC2329  # invocado via trap
_cleanup_boost() {
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh" 2>/dev/null || return 0

  for id in "${created_ads[@]:-}"; do
    [[ -n "$id" ]] || continue
    echo "→ [cleanup] DELETE ad $id"
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 || true
  done
  for id in "${created_creatives[@]:-}"; do
    [[ -n "$id" ]] || continue
    echo "→ [cleanup] DELETE adcreative $id"
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 || true
  done
  for id in "${created_adsets[@]:-}"; do
    [[ -n "$id" ]] || continue
    echo "→ [cleanup] DELETE adset $id"
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 || true
  done
  for id in "${created_campaigns[@]:-}"; do
    [[ -n "$id" ]] || continue
    echo "→ [cleanup] DELETE campaign $id"
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 || true
  done
}
trap _cleanup_boost EXIT

# estado compartilhado entre testes (evita criar creative duplicado)
FEED_MEDIA_ID=""
FEED_CREATIVE_ID=""

# ─── Test 01: listagem de mídia retorna itens com media_product_type ──────────
test_01_list_ig_media() {
  if ! _need_env; then
    _skip "test_01_list_ig_media" "sem env (META_ACCESS_TOKEN/INSTAGRAM_USER_ID)"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local r
  r=$(graph_api GET "${INSTAGRAM_USER_ID}/media?fields=id,media_type,media_product_type,permalink&limit=5") \
    || _fail "test_01_list_ig_media" "GET falhou"
  (( $(echo "$r" | jq '.data | length') >= 1 )) || _fail "test_01_list_ig_media" "sem mídia: $r"
  echo "$r" | jq -e '.data[0] | has("media_product_type")' >/dev/null \
    || _fail "test_01_list_ig_media" "resposta sem media_product_type: $r"
  _pass "test_01_list_ig_media"
}

# ─── Test 02: creative com payload CORRETO (spike 2026-07-boost-ig.md §2.5) ───
# {name, source_instagram_media_id} SOZINHO — sem object_story_spec.
test_02_creative_from_ig_media() {
  if ! _need_env; then
    _skip "test_02_creative_from_ig_media" "sem env"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local media payload r cid
  media=$(graph_api GET "${INSTAGRAM_USER_ID}/media?fields=id,media_product_type&limit=25" \
    | jq -r '.data[] | select(.media_product_type=="FEED") | .id' | head -1)
  if [[ -z "$media" ]]; then
    _skip "test_02_creative_from_ig_media" "sem post FEED na conta"
    return 0
  fi

  payload=$(jq -nc --arg name "TEST_boost_creative_$(date +%s)" --arg m "$media" \
    '{name: $name, source_instagram_media_id: $m}')
  r=$(graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload") \
    || _fail "test_02_creative_from_ig_media" "POST falhou: $r"
  cid=$(echo "$r" | jq -r '.id // empty')
  [[ -n "$cid" ]] || _fail "test_02_creative_from_ig_media" "sem id no response: $r"

  created_creatives+=("$cid")
  FEED_MEDIA_ID="$media"
  FEED_CREATIVE_ID="$cid"
  _pass "test_02_creative_from_ig_media (media=$media, cid=$cid)"
  _sleep_write
}

# ─── Test 03: guarda de regressão — payload do brief original TEM que falhar ──
# object_story_spec{page_id,instagram_user_id} + source_instagram_media_id juntos.
# Spike §2.1: erro idêntico ao de payload sem NENHUMA referência de mídia
# (100/2061015, "campo de link é obrigatório") — a API ignora
# source_instagram_media_id nessa posição. Este teste garante que o SKILL.md
# não regrida pra essa forma quebrada.
test_03_brief_payload_stays_broken() {
  if ! _need_env; then
    _skip "test_03_brief_payload_stays_broken" "sem env"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local media payload r
  media="${FEED_MEDIA_ID}"
  if [[ -z "$media" ]]; then
    media=$(graph_api GET "${INSTAGRAM_USER_ID}/media?fields=id,media_product_type&limit=25" \
      | jq -r '.data[] | select(.media_product_type=="FEED") | .id' | head -1)
  fi
  if [[ -z "$media" ]]; then
    _skip "test_03_brief_payload_stays_broken" "sem post FEED na conta"
    return 0
  fi

  payload=$(jq -nc --arg name "TEST_boost_brief_payload_$(date +%s)" \
    --arg pid "$PAGE_ID" --arg ig "$INSTAGRAM_USER_ID" --arg m "$media" \
    '{name: $name, object_story_spec: {page_id: $pid, instagram_user_id: $ig},
      source_instagram_media_id: $m}')

  # GRAPH_API_SKIP_RESOLVER=1 pra não deixar o error-resolver tentar "consertar"
  # esse payload automaticamente — queremos ver a falha crua.
  if r=$(GRAPH_API_SKIP_RESOLVER=1 graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload" 2>&1); then
    # sucesso inesperado — se criou algo, registra pra cleanup antes de falhar o teste
    local cid
    cid=$(echo "$r" | jq -r '.id // empty')
    [[ -n "$cid" ]] && created_creatives+=("$cid")
    _fail "test_03_brief_payload_stays_broken" \
      "payload do brief (object_story_spec + source_instagram_media_id) CRIOU creative — spike/SKILL.md desatualizados, revisar docs/spikes/2026-07-boost-ig.md §2.1: $r"
  fi
  _pass "test_03_brief_payload_stays_broken (continua rejeitado, como esperado)"
  _sleep_write
}

# ─── Test 04: boost_eligibility_info existe no schema (GET, sem custo) ────────
test_04_boost_eligibility_info_field() {
  if ! _need_env; then
    _skip "test_04_boost_eligibility_info_field" "sem env"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local media r
  media="${FEED_MEDIA_ID}"
  if [[ -z "$media" ]]; then
    media=$(graph_api GET "${INSTAGRAM_USER_ID}/media?fields=id&limit=1" | jq -r '.data[0].id // empty')
  fi
  [[ -n "$media" ]] || { _skip "test_04_boost_eligibility_info_field" "sem mídia disponível"; return 0; }

  r=$(graph_api GET "${media}?fields=boost_eligibility_info") \
    || _fail "test_04_boost_eligibility_info_field" "GET falhou"
  echo "$r" | jq -e '.boost_eligibility_info | has("eligible_to_boost")' >/dev/null \
    || _fail "test_04_boost_eligibility_info_field" "campo ausente/schema mudou: $r"
  _pass "test_04_boost_eligibility_info_field ($r)"
}

# ─── Test 05: reel conhecido do spike como ineligível por música (best-effort) ─
# ID fixo, capturado ao vivo no spike 2026-07-boost-ig.md §4. GET apenas —
# skip gracioso se o post foi apagado ou a elegibilidade mudou desde então
# (estado de conta pode mudar; não é flakiness do teste, é realidade externa).
test_05_known_reel_ineligible_music() {
  if ! _need_env; then
    _skip "test_05_known_reel_ineligible_music" "sem env"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local known_reel="17880349761405800"
  local r elig reason
  if ! r=$(graph_api GET "${known_reel}?fields=id,boost_eligibility_info" 2>&1); then
    _skip "test_05_known_reel_ineligible_music" "reel do spike não acessível mais: $r"
    return 0
  fi
  # NOTA: jq trata `false` como falsy no operador `//` (igual null) — usar
  # `// empty` aqui devolveria vazio pra eligible_to_boost:false e mascararia
  # o próprio caso que este teste existe pra checar. `tostring` evita isso.
  elig=$(echo "$r" | jq -r '.boost_eligibility_info.eligible_to_boost | tostring')
  reason=$(echo "$r" | jq -r '.boost_eligibility_info.boost_ineligible_reason // empty')
  if [[ "$elig" != "false" || -z "$reason" ]]; then
    _skip "test_05_known_reel_ineligible_music" "elegibilidade mudou desde o spike (agora: $r)"
    return 0
  fi
  _pass "test_05_known_reel_ineligible_music (reason=\"$reason\")"
}

# ─── Test 06: cadeia completa campanha→adset(ON_POST)→ad + preview ────────────
test_06_full_chain_adset_on_post() {
  if ! _need_env; then
    _skip "test_06_full_chain_adset_on_post" "sem env"
    return 0
  fi
  if [[ -z "$FEED_CREATIVE_ID" ]]; then
    _skip "test_06_full_chain_adset_on_post" "sem creative do test_02 (dependência)"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  # campanha OUTCOME_ENGAGEMENT
  local camp_payload camp_r camp_id
  camp_payload=$(jq -nc --arg name "TEST_boost_campanha_$(date +%s)" '{
    name: $name, objective: "OUTCOME_ENGAGEMENT", status: "PAUSED",
    special_ad_categories: [], is_adset_budget_sharing_enabled: false
  }')
  camp_r=$(graph_api POST "${AD_ACCOUNT_ID}/campaigns" "$camp_payload") \
    || _fail "test_06_full_chain_adset_on_post" "POST campanha falhou: $camp_r"
  camp_id=$(echo "$camp_r" | jq -r '.id // empty')
  [[ -n "$camp_id" ]] || _fail "test_06_full_chain_adset_on_post" "sem id de campanha: $camp_r"
  created_campaigns+=("$camp_id")
  _sleep_write

  # min_daily_budget real da conta (não hardcode — spike §3.2 confirmou 522 no
  # momento do spike, mas lê ao vivo pra não fossilizar o valor)
  local min_budget
  min_budget=$(graph_api GET "${AD_ACCOUNT_ID}?fields=min_daily_budget" | jq -r '.min_daily_budget // 500')
  local budget=$(( min_budget + 100 ))

  # adset ON_POST / POST_ENGAGEMENT / bid_strategy obrigatório (spike §3.2)
  local adset_payload adset_r adset_id
  adset_payload=$(jq -nc --arg name "TEST_boost_conjunto_$(date +%s)" --arg camp "$camp_id" \
    --arg pid "$PAGE_ID" --argjson budget "$budget" '{
    name: $name, campaign_id: $camp, status: "PAUSED",
    daily_budget: $budget, billing_event: "IMPRESSIONS",
    optimization_goal: "POST_ENGAGEMENT", bid_strategy: "LOWEST_COST_WITHOUT_CAP",
    destination_type: "ON_POST", promoted_object: {page_id: $pid},
    targeting: {
      geo_locations: {countries: ["BR"]}, age_min: 18, age_max: 65,
      targeting_automation: {advantage_audience: 0}
    }
  }')
  adset_r=$(graph_api POST "${AD_ACCOUNT_ID}/adsets" "$adset_payload") \
    || _fail "test_06_full_chain_adset_on_post" "POST adset falhou: $adset_r"
  adset_id=$(echo "$adset_r" | jq -r '.id // empty')
  [[ -n "$adset_id" ]] || _fail "test_06_full_chain_adset_on_post" "sem id de adset: $adset_r"
  created_adsets+=("$adset_id")
  _sleep_write

  # ad reaproveitando o creative do test_02
  local ad_payload ad_r ad_id
  ad_payload=$(jq -nc --arg name "TEST_boost_ad_$(date +%s)" --arg aid "$adset_id" \
    --arg cid "$FEED_CREATIVE_ID" '{
    name: $name, adset_id: $aid, creative: {creative_id: $cid}, status: "PAUSED"
  }')
  ad_r=$(graph_api POST "${AD_ACCOUNT_ID}/ads" "$ad_payload") \
    || _fail "test_06_full_chain_adset_on_post" "POST ad falhou: $ad_r"
  ad_id=$(echo "$ad_r" | jq -r '.id // empty')
  [[ -n "$ad_id" ]] || _fail "test_06_full_chain_adset_on_post" "sem id de ad: $ad_r"
  created_ads+=("$ad_id")

  # preview confirma referência ao post orgânico (GET, sem custo de escrita)
  local preview_r
  preview_r=$(graph_api GET "${ad_id}/previews?ad_format=INSTAGRAM_STANDARD") || true
  echo "$preview_r" | jq -e '.data[0].body | contains("iframe")' >/dev/null \
    || _fail "test_06_full_chain_adset_on_post" "preview sem iframe: $preview_r"

  _pass "test_06_full_chain_adset_on_post (campanha=$camp_id, adset=$adset_id, ad=$ad_id)"
}

# ─── Execução ───────────────────────────────────────────────────────────────
test_01_list_ig_media
test_02_creative_from_ig_media
test_03_brief_payload_stays_broken
test_04_boost_eligibility_info_field
test_05_known_reel_ineligible_music
test_06_full_chain_adset_on_post

echo ""
echo "18-boost-ig: ${PASS} passou, ${FAIL} falhou, ${SKIP} pulados"
(( FAIL == 0 ))
