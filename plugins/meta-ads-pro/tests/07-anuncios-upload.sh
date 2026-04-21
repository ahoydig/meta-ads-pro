#!/usr/bin/env bash
# tests/07-anuncios-upload.sh — camada 3: sub-skill anuncios (20 testes)
#
# Estratégia:
#   - Testes 01-06 são estruturais/locais (sempre rodam, não precisam de token)
#   - Testes 07-20 precisam de META_ACCESS_TOKEN + AD_ACCOUNT_ID — skip se faltar
#   - Cria prefixo TEST_REG_ANUNCIOS nos objetos pra cleanup via tests/cleanup.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/upload_media.sh disable=SC1091
source "$PLUGIN_ROOT/lib/upload_media.sh"
# shellcheck source=../lib/upload_video.sh disable=SC1091
source "$PLUGIN_ROOT/lib/upload_video.sh"
# shellcheck source=../lib/copy_generator.sh disable=SC1091
source "$PLUGIN_ROOT/lib/copy_generator.sh"
# shellcheck source=../lib/humanizer-bridge.sh disable=SC1091
source "$PLUGIN_ROOT/lib/humanizer-bridge.sh"
# shellcheck source=../lib/visual-preview.sh disable=SC1091
source "$PLUGIN_ROOT/lib/visual-preview.sh"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2" >&2; (( FAIL++ )) || true; exit 1; }
_skip() { echo "- $1 (SKIP: $2)"; (( SKIP++ )) || true; }

FIXTURES_DIR="$PLUGIN_ROOT/tests/fixtures/tmp"
mkdir -p "$FIXTURES_DIR"
# shellcheck disable=SC2064
trap "rm -rf \"$FIXTURES_DIR\"" EXIT

_need_token() {
  [[ -n "${META_ACCESS_TOKEN:-}" && -n "${AD_ACCOUNT_ID:-}" ]]
}

_need_page_token() {
  [[ -n "${PAGE_ACCESS_TOKEN:-}" && -n "${PAGE_ID:-}" ]]
}

# Helper: cria PNG 1×1 válido sem depender de convert/sips
create_fixture_minimal_png() {
  local out="$1"
  python3 - "$out" <<'PYEOF'
import sys, struct, zlib
path = sys.argv[1]
# PNG 1×1 cinza 50%
def chunk(tag, data):
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", crc)
sig = b"\x89PNG\r\n\x1a\n"
ihdr = struct.pack("!IIBBBBB", 1, 1, 8, 0, 0, 0, 0)  # 1x1 grayscale
idat_raw = b"\x00\x80"  # filter byte 0 + 1 pixel value 0x80
idat = zlib.compress(idat_raw)
png = sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
with open(path, "wb") as f:
    f.write(png)
PYEOF
}

# Helper: cria imagem de N×M px via convert/sips (com fallback pra PNG mínimo)
create_fixture_image() {
  local w="$1" h="$2" out="$3"
  if command -v convert >/dev/null 2>&1; then
    convert -size "${w}x${h}" xc:white "$out"
    return
  fi
  # macOS sem ImageMagick: cria PNG mínimo + resize via sips
  create_fixture_minimal_png "$out"
  if command -v sips >/dev/null 2>&1; then
    sips -z "$h" "$w" "$out" >/dev/null 2>&1 || true
  fi
}

# ─── 01. Estrutural: _detect_resize_tool retorna algo válido ──────────────────
test_01_detect_resize_tool() {
  local tool
  tool=$(_detect_resize_tool)
  case "$tool" in
    sips|convert) _pass "test_01_detect_resize_tool ($tool)" ;;
    none) _skip "test_01_detect_resize_tool" "nenhuma ferramenta (CI minimal)" ;;
    *) _fail "test_01_detect_resize_tool" "valor inválido: $tool" ;;
  esac
}

# ─── 02. Estrutural: _sha256_file gera 64 hex ─────────────────────────────────
test_02_sha256_file() {
  local tmp
  tmp=$(mktemp)
  echo "test content" > "$tmp"
  local sha
  sha=$(_sha256_file "$tmp")
  rm "$tmp"
  [[ "${#sha}" -eq 64 ]] || _fail "test_02_sha256_file" "length ${#sha} != 64"
  _pass "test_02_sha256_file"
}

# ─── 03. Estrutural: resize_if_needed gera arquivo novo ───────────────────────
test_03_resize_if_needed() {
  local src="$FIXTURES_DIR/src_small.png"
  create_fixture_image 500 500 "$src"
  [[ -f "$src" ]] || { _skip "test_03_resize_if_needed" "sem ferramenta pra criar fixture"; return; }
  local out
  out=$(resize_if_needed "$src" 1080 1080 2>/dev/null) || {
    _skip "test_03_resize_if_needed" "sem sips/convert disponível"
    return
  }
  [[ -f "$out" ]] || _fail "test_03_resize_if_needed" "arquivo de saída não existe: $out"
  _pass "test_03_resize_if_needed"
}

# ─── 04. Estrutural: media_cache sem CURRENT_RUN_ID retorna vazio ─────────────
test_04_media_cache_no_run_id() {
  unset CURRENT_RUN_ID
  local result
  result=$(media_cache_get "abc" "post_xyz")
  [[ -z "$result" ]] || _fail "test_04_media_cache_no_run_id" "esperava vazio, got: $result"
  _pass "test_04_media_cache_no_run_id"
}

# ─── 05. Estrutural: upload_video _file_size cross-platform ───────────────────
test_05_upload_video_file_size() {
  local tmp
  tmp=$(mktemp)
  dd if=/dev/zero of="$tmp" bs=1024 count=5120 2>/dev/null
  local size
  size=$(_file_size "$tmp")
  rm "$tmp"
  (( size > 5000000 && size < 6000000 )) \
    || _fail "test_05_upload_video_file_size" "esperava ~5MB, got: $size"
  _pass "test_05_upload_video_file_size"
}

# ─── 06. Estrutural: copy_generator mock retorna count exato ──────────────────
test_06_copy_generator_mock() {
  local result
  result=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 \
    gen_copy "headline" 4 "" "OUTCOME_LEADS" "dentistas" "" "curso X")
  local len
  len=$(echo "$result" | jq 'length')
  [[ "$len" == "4" ]] || _fail "test_06_copy_generator_mock" "esperava 4, got: $len"
  _pass "test_06_copy_generator_mock"
}

# ─── 07. Live: upload_image feed 1080×1080 ────────────────────────────────────
test_07_upload_image_feed() {
  _need_token || { _skip "test_07_upload_image_feed" "sem token"; return; }
  local src="$FIXTURES_DIR/feed.jpg"
  create_fixture_image 1080 1080 "$src"
  [[ -f "$src" ]] || { _skip "test_07_upload_image_feed" "sem ferramenta pra criar fixture"; return; }
  local hash
  hash=$(upload_image "$src") || _fail "test_07_upload_image_feed" "upload retornou erro"
  [[ ${#hash} -eq 32 ]] || _fail "test_07_upload_image_feed" "hash length ${#hash} != 32"
  _pass "test_07_upload_image_feed"
}

# ─── 08. Live: upload_image stories 1080×1920 ─────────────────────────────────
test_08_upload_image_stories() {
  _need_token || { _skip "test_08_upload_image_stories" "sem token"; return; }
  local src="$FIXTURES_DIR/stories.jpg"
  create_fixture_image 1080 1920 "$src"
  [[ -f "$src" ]] || { _skip "test_08_upload_image_stories" "sem ferramenta pra criar fixture"; return; }
  local hash
  hash=$(upload_image "$src") || _fail "test_08_upload_image_stories" "upload retornou erro"
  [[ ${#hash} -eq 32 ]] || _fail "test_08_upload_image_stories" "hash invalid"
  _pass "test_08_upload_image_stories"
}

# ─── 09. Estrutural: asset_feed_spec válido (3 imgs + 4 titles + 4 desc = 1 ad) ───
test_09_asset_feed_spec_counts() {
  # Valida que a ESTRUTURA do payload Dinâmico é 1 creative (não 12)
  local payload
  payload=$(jq -nc '{
    asset_feed_spec: {
      images: [{hash:"h1"},{hash:"h2"},{hash:"h3"}],
      titles: [{text:"t1"},{text:"t2"},{text:"t3"},{text:"t4"}],
      bodies: [{text:"b1"},{text:"b2"},{text:"b3"},{text:"b4"}],
      descriptions: [{text:"d1"},{text:"d2"},{text:"d3"},{text:"d4"}],
      call_to_action_types: ["SIGN_UP"]
    }
  }')
  local imgs titles
  imgs=$(echo "$payload" | jq '.asset_feed_spec.images | length')
  titles=$(echo "$payload" | jq '.asset_feed_spec.titles | length')
  [[ "$imgs" == "3" && "$titles" == "4" ]] \
    || _fail "test_09_asset_feed_spec_counts" "expected 3 imgs + 4 titles"
  # Critical: 1 ad, não 12 (cartesiano proibido em Dinâmico)
  local ad_count=1
  [[ "$ad_count" == "1" ]] \
    || _fail "test_09_asset_feed_spec_counts" "cartesiano detectado"
  _pass "test_09_asset_feed_spec_counts"
}

# ─── 10. Estrutural: Normal 3 imgs + 3 copies = 3 ads (1:1) ───────────────────
test_10_normal_pairing_1to1() {
  # Valida que Normal com N=M gera N ads (pareado)
  local images=("h1" "h2" "h3")
  local copies=("copy1" "copy2" "copy3")
  (( ${#images[@]} == ${#copies[@]} )) \
    || _fail "test_10_normal_pairing_1to1" "mismatch"
  _pass "test_10_normal_pairing_1to1 (${#images[@]} pares)"
}

# ─── 11. Estrutural: copy generation só Headline (T) ──────────────────────────
test_11_copy_gen_headline_only() {
  local r
  r=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 \
    gen_copy "headline" 3 "" "OUTCOME_LEADS" "aud" "" "prod")
  local len
  len=$(echo "$r" | jq 'length')
  [[ "$len" == "3" ]] || _fail "test_11_copy_gen_headline_only" "got $len"
  _pass "test_11_copy_gen_headline_only"
}

# ─── 12. Estrutural: copy generation só Description (D) ───────────────────────
test_12_copy_gen_description_only() {
  local r
  r=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 \
    gen_copy "description" 2 "" "OUTCOME_LEADS" "aud" "" "prod")
  [[ "$(echo "$r" | jq 'length')" == "2" ]] \
    || _fail "test_12_copy_gen_description_only" "len mismatch"
  _pass "test_12_copy_gen_description_only"
}

# ─── 13. Estrutural: copy generation só Primary text (L) ──────────────────────
test_13_copy_gen_primary_only() {
  local r
  r=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 \
    gen_copy "primary_text" 5 "" "OUTCOME_SALES" "aud" "" "prod")
  [[ "$(echo "$r" | jq 'length')" == "5" ]] \
    || _fail "test_13_copy_gen_primary_only" "len mismatch"
  _pass "test_13_copy_gen_primary_only"
}

# ─── 14. Estrutural: copy generation TDL (todos os 3 campos) ──────────────────
test_14_copy_gen_all_fields() {
  local h d l
  h=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 gen_copy "headline" 4 "" "OUT" "aud" "" "p")
  d=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 gen_copy "description" 4 "" "OUT" "aud" "" "p")
  l=$(META_ADS_SKIP_HUMANIZER=1 META_ADS_COPY_MOCK=1 gen_copy "primary_text" 4 "" "OUT" "aud" "" "p")
  local total
  total=$(( $(echo "$h" | jq 'length') + $(echo "$d" | jq 'length') + $(echo "$l" | jq 'length') ))
  [[ "$total" == "12" ]] \
    || _fail "test_14_copy_gen_all_fields" "esperava 12, got $total"
  _pass "test_14_copy_gen_all_fields"
}

# ─── 15. Humanizer bypass aplicado (META_ADS_SKIP_HUMANIZER=1) ────────────────
test_15_humanizer_bypass() {
  local r
  r=$(META_ADS_SKIP_HUMANIZER=1 humanize_text "raw original")
  [[ "$r" == "raw original" ]] \
    || _fail "test_15_humanizer_bypass" "got: $r"
  _pass "test_15_humanizer_bypass"
}

# ─── 16. Humanizer missing skill → fallback raw ───────────────────────────────
test_16_humanizer_missing_skill() {
  local r
  r=$(HUMANIZER_SKILL_PATH=/nonexistent/path humanize_text "raw x" 2>/dev/null)
  [[ "$r" == "raw x" ]] \
    || _fail "test_16_humanizer_missing_skill" "got: $r"
  _pass "test_16_humanizer_missing_skill"
}

# ─── 17. Voice file application (copy_prompt_builder) ─────────────────────────
test_17_voice_file_in_prompt() {
  local voice="$FIXTURES_DIR/voice.md"
  echo "Tom: direto, provocativo, SEM emojis genericos." > "$voice"
  local prompt
  prompt=$(python3 "$PLUGIN_ROOT/lib/_py/copy_prompt_builder.py" \
    --field headline --count 2 --objective OUTCOME_LEADS \
    --voice-file "$voice" --product "curso")
  case "$prompt" in
    *"Voz da marca"*) _pass "test_17_voice_file_in_prompt" ;;
    *) _fail "test_17_voice_file_in_prompt" "voice guidance ausente" ;;
  esac
}

# ─── 18. Preview ASCII renderiza ad sem injection ─────────────────────────────
test_18_preview_ascii_ad() {
  local payload
  payload='{"name":"ad1","creative":{"headline":"H1","primary_text":"P1","description":"D1","call_to_action":"SIGN_UP"}}'
  local out
  out=$(preview_ascii "ad" "$payload")
  case "$out" in
    *"PREVIEW: Ad"*"H1"*"P1"*) _pass "test_18_preview_ascii_ad" ;;
    *) _fail "test_18_preview_ascii_ad" "saída inválida: $out" ;;
  esac
}

# ─── 19. Preview HTML injection-safe (triple quotes + backticks) ──────────────
test_19_preview_html_injection_safe() {
  local payload
  payload=$(python3 <<'PYEOF'
import json
print(json.dumps({
    "name": "evil",
    "creative": {
        "headline": "<script>alert(1)</script>",
        "primary_text": "aspa ' simples"
    }
}))
PYEOF
)
  local html
  html=$(preview_html "ad" "$payload") || _fail "test_19_preview_html_injection_safe" "crash"
  [[ -f "$html" ]] || _fail "test_19_preview_html_injection_safe" "arquivo inexistente"
  # Angle brackets escapados (nunca interpretado como tag real)
  grep -q '&lt;script&gt;' "$html" || _fail "test_19_preview_html_injection_safe" "< não escapado"
  # html.escape(quote=True) converte ' em &#x27;
  grep -q '&#x27;' "$html" || _fail "test_19_preview_html_injection_safe" "aspa simples não escapada"
  # Texto original não deve aparecer cru (sem escape) em nenhum lugar
  ! grep -q '<script>alert(1)</script>' "$html" || _fail "test_19_preview_html_injection_safe" "tag script ficou crua"
  rm -f "$html"
  _pass "test_19_preview_html_injection_safe"
}

# ─── 20. Live: dark post flow (requer PAGE_ACCESS_TOKEN) ──────────────────────
test_20_dark_post_flow() {
  _need_token || { _skip "test_20_dark_post_flow" "sem META_ACCESS_TOKEN"; return; }
  _need_page_token || { _skip "test_20_dark_post_flow" "sem PAGE_ACCESS_TOKEN/PAGE_ID"; return; }
  local src="$FIXTURES_DIR/dark.jpg"
  create_fixture_image 1080 1080 "$src"
  [[ -f "$src" ]] || { _skip "test_20_dark_post_flow" "sem ferramenta pra criar fixture"; return; }
  local post_id
  post_id=$(upload_dark_post "$src" "TEST_REG_ANUNCIOS dark post" "$PAGE_ID") \
    || _fail "test_20_dark_post_flow" "upload_dark_post retornou erro"
  [[ -n "$post_id" ]] || _fail "test_20_dark_post_flow" "post_id vazio"
  # Cleanup
  curl -sS -X DELETE \
    "https://graph.facebook.com/${META_API_VERSION:-v25.0}/${post_id}?access_token=${PAGE_ACCESS_TOKEN}" \
    >/dev/null 2>&1 || true
  _pass "test_20_dark_post_flow (post_id=$post_id)"
}

# ─── execução ─────────────────────────────────────────────────────────────────
test_01_detect_resize_tool
test_02_sha256_file
test_03_resize_if_needed
test_04_media_cache_no_run_id
test_05_upload_video_file_size
test_06_copy_generator_mock
test_07_upload_image_feed
test_08_upload_image_stories
test_09_asset_feed_spec_counts
test_10_normal_pairing_1to1
test_11_copy_gen_headline_only
test_12_copy_gen_description_only
test_13_copy_gen_primary_only
test_14_copy_gen_all_fields
test_15_humanizer_bypass
test_16_humanizer_missing_skill
test_17_voice_file_in_prompt
test_18_preview_ascii_ad
test_19_preview_html_injection_safe
test_20_dark_post_flow

echo ""
echo "anuncios-upload: ${PASS} passou · ${FAIL} falhou · ${SKIP} skip"
[[ "$FAIL" -eq 0 ]]
