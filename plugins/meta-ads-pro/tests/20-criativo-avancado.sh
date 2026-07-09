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
# Orçamento de chamadas (Task 14): 100% GET (generatepreviews + previews +
# listagem de adcreatives). Nenhum POST/DELETE.
#
# Task 15 acrescenta (mesmo arquivo, nomes `test_02_image_crops` e
# `test_03_asset_customization_rules` conforme o brief — não confundir com
# `test_02_generatepreviews_instagram_standard`/`test_03_previews_existing_creative_id`
# acima, que são da Task 14):
#   - test_02_image_crops: creative Normal com `image_crops` (crop 1:1
#     explícito de uma fixture retrato). 1 upload + 1 POST /adcreatives + 1 GET.
#   - test_03_asset_customization_rules: creative Dinâmico com
#     `asset_feed_spec.asset_customization_rules` (imagem por grupo de
#     placements via adlabels). 2 uploads + 1 POST /adcreatives.
# Ambos usam o array `created_creatives` + trap de cleanup (DELETE no EXIT).
#
# Task 16 acrescenta `test_05_carousel` (próximo índice livre — 01/02/02/03/03/04
# já usados por T14/T15): modo Carrossel via `child_attachments`. 1 upload +
# POST /adcreatives com 3 cartões (`multi_share_optimized`/`multi_share_end_card`)
# + GET round-trip (`child_attachments.length == 3`) + cleanup. Ver comentário
# na função pra decisão hash-reusado-vs-3-uploads.
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

# ─── Test 02 (nome do brief da Task 15): creative Normal com image_crops ──────
# Crop 1:1 centrado. A fixture real (`tests/fixtures/`) não tem uma imagem
# 1200x800 como o brief original supunha — só `seed_1080.jpg` (1080x1080,
# já quadrada) e `seed_1080x1920.jpg` (1080x1920, retrato). Usamos a retrato
# pra exercitar o crop de verdade: janela quadrada central de 1080x1080 dentro
# dos 1080x1920 tem margem superior (1920-1080)/2 = 420px → [[0,420],[1080,1500]].
# Key "100x100" = aspect ratio alvo 1:1 (não é tamanho em px).
#
# DIVERGÊNCIA vs. o brief: `image_crops` **não** funciona como campo top-level
# do creative (testado ao vivo — POST aceita e devolve 201, mas o GET seguinte
# retorna objeto vazio; a Meta ignora silenciosamente). O campo real precisa
# estar ANINHADO dentro de `object_story_spec.link_data.image_crops` — só aí
# persiste e some a espelhar também no `image_crops` top-level no GET. Doc
# oficial (ads-commerce/marketing-api/image-crops) confirma esse shape.
# Ver apêndice em docs/spikes/2026-07-api-version.md.
test_02_image_crops() {
  if ! _need_env; then
    _skip "test_02_image_crops" "sem env"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"
  # shellcheck source=../lib/upload_media.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/upload_media.sh"
  local fixture hash payload r cid
  fixture=$(ls "$PLUGIN_ROOT"/tests/fixtures/seed_1080x1920.jpg 2>/dev/null | head -1)
  [[ -n "$fixture" ]] || { _skip "test_02_image_crops" "sem fixture seed_1080x1920.jpg"; return 0; }
  hash=$(upload_image "$fixture") || _fail "test_02_image_crops" "upload falhou"
  payload=$(jq -nc --arg pid "$PAGE_ID" --arg h "$hash" '{
    name:"TEST_crops",
    object_story_spec:{page_id:$pid,
      link_data:{message:"crop test", link:"https://ahoy.digital", image_hash:$h,
        image_crops:{"100x100":[[0,420],[1080,1500]]}}}}')
  r=$(graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload") \
    || _fail "test_02_image_crops" "POST falhou: $r"
  cid=$(echo "$r" | jq -r .id); created_creatives+=("$cid")
  # Round-trip: 1 GET só, verificando (a) o lugar CERTO diretamente (campo
  # aninhado em object_story_spec.link_data) com igualdade EXATA do valor
  # enviado — não só presença — e (b) o espelho top-level read-only.
  local got
  got=$(graph_api GET "${cid}?fields=object_story_spec,image_crops") \
    || _fail "test_02_image_crops" "GET round-trip falhou: $got"
  echo "$got" | jq -e '.object_story_spec.link_data.image_crops["100x100"] == [[0,420],[1080,1500]]' >/dev/null \
    || _fail "test_02_image_crops" "image_crops aninhado ausente ou != enviado: $got"
  echo "$got" | jq -e '.image_crops["100x100"] == [[0,420],[1080,1500]]' >/dev/null \
    || _fail "test_02_image_crops" "espelho top-level image_crops ausente ou != enviado: $got"
  _pass "test_02_image_crops (cid=$cid)"
}

# ─── Test 03 (nome do brief da Task 15): asset_customization_rules ────────────
# asset_feed_spec com 2 imagens rotuladas via adlabels (img_feed / img_story) +
# 2 asset_customization_rules que direcionam cada imagem pra um grupo de
# placements (feed vs story). Fixtures reais: seed_1080.jpg (f1) e
# seed_1080x1920.jpg (f2) — os globs do brief original (`*1080x1080*.jpg`) não
# batiam com o nome real das fixtures, corrigido pros nomes literais.
test_03_asset_customization_rules() {
  if ! _need_env; then
    _skip "test_03_asset_customization_rules" "sem env"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"
  # shellcheck source=../lib/upload_media.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/upload_media.sh"
  local f1 f2 h1 h2 payload r cid
  f1=$(ls "$PLUGIN_ROOT"/tests/fixtures/seed_1080.jpg 2>/dev/null | head -1)
  f2=$(ls "$PLUGIN_ROOT"/tests/fixtures/seed_1080x1920.jpg 2>/dev/null | head -1)
  [[ -n "$f1" && -n "$f2" ]] || { _skip "test_03_asset_customization_rules" "sem fixtures 1080"; return 0; }
  h1=$(upload_image "$f1") || _fail "test_03_asset_customization_rules" "upload f1 falhou"
  h2=$(upload_image "$f2") || _fail "test_03_asset_customization_rules" "upload f2 falhou"
  payload=$(jq -nc --arg pid "$PAGE_ID" --arg h1 "$h1" --arg h2 "$h2" '{
    name:"TEST_asset_custom",
    object_story_spec:{page_id:$pid},
    asset_feed_spec:{
      images:[{hash:$h1, adlabels:[{name:"img_feed"}]},
              {hash:$h2, adlabels:[{name:"img_story"}]}],
      bodies:[{text:"corpo"}], titles:[{text:"titulo"}],
      link_urls:[{website_url:"https://ahoy.digital"}],
      call_to_action_types:["LEARN_MORE"],
      ad_formats:["SINGLE_IMAGE"],
      asset_customization_rules:[
        {customization_spec:{publisher_platforms:["facebook","instagram"],
           facebook_positions:["feed"], instagram_positions:["stream"]},
         image_label:{name:"img_feed"}},
        {customization_spec:{publisher_platforms:["facebook","instagram"],
           facebook_positions:["story"], instagram_positions:["story"]},
         image_label:{name:"img_story"}}]}}')
  r=$(graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload") \
    || _fail "test_03_asset_customization_rules" "POST falhou: $r"
  cid=$(echo "$r" | jq -r .id); created_creatives+=("$cid")
  _pass "test_03_asset_customization_rules (cid=$cid)"
}

# ─── Test 05: modo Carrossel via child_attachments (Task 16) ─────────────────
# Payload do brief: object_story_spec.link_data com child_attachments[3]
# (link+image_hash+name+description cada), multi_share_optimized:true,
# multi_share_end_card:false. UTM estático de teste embutido no `link` principal
# e em CADA `child_attachments[].link` (no fluxo real isso é UTM DINÂMICO via
# `build_utm_url_dynamic`, por cartão — ver SKILL.md "Modo Carrossel"; aqui é só
# um valor fixo de teste, não passa pelo helper).
#
# DECISÃO hash-reusado vs. 3 uploads: testado ao vivo — 1 UPLOAD (seed_1080.jpg)
# + a MESMA image_hash repetida nos 3 cartões É aceita pela Meta (POST 201, GET
# round-trip confirma os 3 child_attachments com o hash idêntico). Preferido a
# 3 uploads (ou 2 variações via sips) porque o que este teste cobre é o SHAPE
# do payload (3 cartões, campos certos, flags certas) — não a distinção visual
# entre imagens, que não é testável via assert de API. Poupa 2 writes.
test_05_carousel() {
  if ! _need_env; then
    _skip "test_05_carousel" "sem env"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"
  # shellcheck source=../lib/upload_media.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/upload_media.sh"
  local fixture hash payload r cid
  fixture=$(ls "$PLUGIN_ROOT"/tests/fixtures/seed_1080.jpg 2>/dev/null | head -1)
  [[ -n "$fixture" ]] || { _skip "test_05_carousel" "sem fixture seed_1080.jpg"; return 0; }
  hash=$(upload_image "$fixture") || _fail "test_05_carousel" "upload falhou"
  payload=$(jq -nc --arg pid "$PAGE_ID" --arg h "$hash" '{
    name:"TEST_carousel",
    object_story_spec:{page_id:$pid,
      link_data:{
        message:"Legenda do carrossel",
        link:"https://ahoy.digital?utm_source=meta&utm_medium=trafego-pago&utm_campaign=test_carousel",
        child_attachments:[
          {link:"https://ahoy.digital/a?utm_source=meta&utm_medium=trafego-pago&utm_campaign=test_carousel", image_hash:$h, name:"Card 1", description:"Desc 1"},
          {link:"https://ahoy.digital/b?utm_source=meta&utm_medium=trafego-pago&utm_campaign=test_carousel", image_hash:$h, name:"Card 2", description:"Desc 2"},
          {link:"https://ahoy.digital/c?utm_source=meta&utm_medium=trafego-pago&utm_campaign=test_carousel", image_hash:$h, name:"Card 3", description:"Desc 3"}
        ],
        multi_share_optimized:true,
        multi_share_end_card:false
      }}}')
  r=$(graph_api POST "${AD_ACCOUNT_ID}/adcreatives" "$payload") \
    || _fail "test_05_carousel" "POST falhou: $r"
  cid=$(echo "$r" | jq -r .id); created_creatives+=("$cid")
  local got
  got=$(graph_api GET "${cid}?fields=object_story_spec") \
    || _fail "test_05_carousel" "GET round-trip falhou: $got"
  echo "$got" | jq -e '(.object_story_spec.link_data.child_attachments | length) == 3' >/dev/null \
    || _fail "test_05_carousel" "child_attachments ausente ou length != 3: $got"
  # Round-trip POR CAMPO (fix pós-review, precedente da T15: a API desta área já
  # dropou campo em silêncio com 201). Cada cartão: name/description/image_hash
  # com igualdade EXATA contra o enviado; link com prefixo (startswith) + a
  # presença do utm_campaign — é o link que carrega o UTM por cartão, então
  # truncamento/drop dele é exatamente o que este assert pega. Observado ao
  # vivo: os links dos cartões voltam byte-idênticos ao enviado (só o `link`
  # principal sem path ganha "/" — ahoy.digital → ahoy.digital/).
  echo "$got" | jq -e --arg h "$hash" '
    .object_story_spec.link_data.child_attachments as $c |
    ($c[0].name == "Card 1" and $c[0].description == "Desc 1" and $c[0].image_hash == $h
      and ($c[0].link | startswith("https://ahoy.digital/a?"))
      and ($c[0].link | contains("utm_campaign=test_carousel"))) and
    ($c[1].name == "Card 2" and $c[1].description == "Desc 2" and $c[1].image_hash == $h
      and ($c[1].link | startswith("https://ahoy.digital/b?"))
      and ($c[1].link | contains("utm_campaign=test_carousel"))) and
    ($c[2].name == "Card 3" and $c[2].description == "Desc 3" and $c[2].image_hash == $h
      and ($c[2].link | startswith("https://ahoy.digital/c?"))
      and ($c[2].link | contains("utm_campaign=test_carousel")))' >/dev/null \
    || _fail "test_05_carousel" "campo de cartão divergente do enviado no round-trip: $got"
  _pass "test_05_carousel (cid=$cid)"
}

# ─── Execução ───────────────────────────────────────────────────────────────
# sleep leve entre testes GET (baratos); sleep maior antes dos testes que
# escrevem (upload + adcreatives, T15) — outro track pode usar a mesma conta
# (ver nota no brief da task).
test_01_generatepreviews
sleep "${CRIATIVO_TEST_READ_SLEEP:-5}"
test_02_generatepreviews_instagram_standard
sleep "${CRIATIVO_TEST_READ_SLEEP:-5}"
test_03_previews_existing_creative_id
sleep "${CRIATIVO_TEST_READ_SLEEP:-5}"
test_04_preview_meta_oficial_gera_html
sleep "${CRIATIVO_TEST_WRITE_SLEEP:-15}"
test_02_image_crops
sleep "${CRIATIVO_TEST_WRITE_SLEEP:-15}"
test_03_asset_customization_rules
sleep "${CRIATIVO_TEST_WRITE_SLEEP:-15}"
test_05_carousel

echo ""
echo "20-criativo-avancado: ${PASS} passou, ${FAIL} falhou, ${SKIP} pulados"
(( FAIL == 0 ))
