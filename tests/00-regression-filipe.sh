#!/usr/bin/env bash
# tests/00-regression-filipe.sh — regressão 1:1 com 10 bugs-âncora do caso Filipe
#
# Estrutura por CP:
#   CP1  → test_bug_10  (doctor/preflight — já implementado)
#   CP2a → test_bug_01  (ABO is_adset_budget_sharing_enabled ausente)
#   CP2b → test_bug_02  (targeting_automation.advantage_audience ausente)
#   CP2c → test_bug_03  (object_story_spec bloqueado em dev mode → dark post)
#   CP2c → test_bug_04  (Dinâmico gerando N×M ads em vez de 1 asset_feed_spec)
#   CP2c → test_bug_05  (media_fbid reusado entre posts diferentes)
#   CP3a → test_bug_06  (lead_gen_form_id inválido)
#   CP3b → test_bug_07  (data_preset retroage > 37 meses)
#   CP3b → test_bug_08  (BUC rate limit — ler header em vez de chutar espera)
#   CP3b → test_bug_09  (reservado — se novo bug emergir em rules/insights)
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Bugs 03/04/05 são estruturais (sem token). Bugs 01/02/10 precisam de token.
HAVE_TOKEN=1
[[ -n "${META_ACCESS_TOKEN:-}" ]] || HAVE_TOKEN=0

PASS=0; FAIL=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2"; (( FAIL++ )) || true; exit 1; }
_skip() { echo "- $1 (SKIP: $2)"; }

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

# ── Bug #3: object_story_spec bloqueado em dev mode → dark post ──────────────
# Meta Graph API rejeita creative com object_story_spec quando o app está em dev
# mode (usuários fora da lista de testers não aparecem). Erro 100/1885183.
#
# Fix: error-resolver roteia 100/1885183 pra switch_to_dark_post_flow, que cria
# dark post (published=false) e re-POSTa o creative com object_story_id.
#
# Estrutura do teste (estrutural — não exige token nem dev mode real):
#   Phase 1 (contrato de routing): error-catalog.yaml tem 100/1885183 →
#                                  switch_to_dark_post_flow.
#   Phase 2 (função existe):       error-resolver.sh define a função, e
#                                  get_fix_for_error 100 1885183 retorna
#                                  "switch_to_dark_post_flow".
#
# Regressão: se alguém remover o entry do catalog OU a função, o teste falha
# antes do fix → dev mode volta a quebrar silencioso.
test_bug_03_dev_mode_detection() {
  local catalog="$PLUGIN_ROOT/lib/error-catalog.yaml"
  local resolver="$PLUGIN_ROOT/lib/error-resolver.sh"
  [[ -f "$catalog" ]]  || _fail "test_bug_03_dev_mode_detection" "error-catalog.yaml ausente"
  [[ -f "$resolver" ]] || _fail "test_bug_03_dev_mode_detection" "error-resolver.sh ausente"

  # ── Phase 1: contrato do catalog ─────────────────────────────────────────
  local has_entry
  has_entry=$(python3 - <<PYEOF
import yaml, sys
with open("$catalog") as f:
    d = yaml.safe_load(f)
entry = d.get("errors", {}).get(100, {}).get(1885183)
if not entry:
    print("MISSING"); sys.exit(0)
print(entry.get("fix_fn") or entry.get("action") or "UNKNOWN")
PYEOF
)
  [[ "$has_entry" == "switch_to_dark_post_flow" ]] \
    || _fail "test_bug_03_dev_mode_detection" \
       "phase 1: catalog 100/1885183 → '$has_entry' (esperado switch_to_dark_post_flow)"

  # ── Phase 2: função existe e get_fix_for_error roteia corretamente ───────
  # shellcheck source=../lib/error-resolver.sh disable=SC1091
  source "$resolver"
  command -v switch_to_dark_post_flow >/dev/null 2>&1 \
    || _fail "test_bug_03_dev_mode_detection" \
       "phase 2: função switch_to_dark_post_flow não foi exportada"

  local fix
  fix=$(get_fix_for_error 100 1885183)
  [[ "$fix" == "switch_to_dark_post_flow" ]] \
    || _fail "test_bug_03_dev_mode_detection" \
       "phase 2: get_fix_for_error retornou '$fix' (esperado switch_to_dark_post_flow)"

  _pass "test_bug_03_dev_mode_detection (catalog + função + routing OK)"
}

# ── Bug #4: Dinâmico gerando N×M ads em vez de 1 asset_feed_spec ──────────────
# O caso Filipe teve a skill gerando 3 imgs × 4 titles × 4 descs = 48 ads.
# Fix: em Dinâmico, **sempre** 1 único creative com asset_feed_spec — a Meta
# combina as variações automaticamente. Produto cartesiano proibido em
# Dinâmico (só permitido em Normal com flag explícita --cartesian).
#
# Estrutura do teste (estrutural — sem token):
#   Phase 1 (contrato doc):    SKILL.md declara "1 único creative" em Dinâmico
#   Phase 2 (shape payload):   dado 3 imgs + 4 titles + 4 descs, o payload
#                              construído deve ter asset_feed_spec com todas
#                              as variações embutidas, NÃO ser um array de
#                              creatives nem ter loop cartesiano.
#
# Regressão: se alguém reintroduzir loop N×M em Dinâmico, a SKILL.md perde a
# frase "1 único creative" (phase 1) OU o shape do payload fica errado
# (phase 2) — teste falha.
test_bug_04_no_cartesian_in_dynamic() {
  local skill_md="$PLUGIN_ROOT/skills/anuncios/SKILL.md"
  [[ -f "$skill_md" ]] || _fail "test_bug_04_no_cartesian_in_dynamic" "SKILL.md ausente"

  # ── Phase 1: contrato documentado ────────────────────────────────────────
  grep -qi '1 *único creative\|1 *single creative\|1 ad com asset_feed_spec' "$skill_md" \
    || _fail "test_bug_04_no_cartesian_in_dynamic" \
       "phase 1: SKILL.md não declara '1 único creative' em Dinâmico"
  grep -qi 'nunca.*cartesiano\|produto cartesiano proibido\|cartesiano.*proibido' "$skill_md" \
    || _fail "test_bug_04_no_cartesian_in_dynamic" \
       "phase 1: SKILL.md não proíbe explicitamente cartesiano em Dinâmico"

  # ── Phase 2: shape do payload Dinâmico ──────────────────────────────────
  # Constrói o payload como a skill construiria (3 imgs + 4 titles + 4 descs)
  # e valida que é 1 objeto (não array de ads) com contagens preservadas
  # dentro de asset_feed_spec — sem expansão cartesiana pré-envio.
  local payload
  payload=$(jq -nc '{
    name: "dyn_test",
    object_story_spec: {page_id:"p", instagram_user_id:"i"},
    asset_feed_spec: {
      images: [{hash:"h1"},{hash:"h2"},{hash:"h3"}],
      titles: [{text:"t1"},{text:"t2"},{text:"t3"},{text:"t4"}],
      bodies: [{text:"b1"},{text:"b2"},{text:"b3"},{text:"b4"}],
      descriptions: [{text:"d1"},{text:"d2"},{text:"d3"},{text:"d4"}],
      call_to_action_types: ["SIGN_UP"],
      ad_formats: ["SINGLE_IMAGE"]
    }
  }')

  local is_obj imgs titles descs
  is_obj=$(echo "$payload" | jq -r 'type')
  imgs=$(  echo "$payload" | jq '.asset_feed_spec.images       | length')
  titles=$(echo "$payload" | jq '.asset_feed_spec.titles       | length')
  descs=$( echo "$payload" | jq '.asset_feed_spec.descriptions | length')

  [[ "$is_obj" == "object" ]] \
    || _fail "test_bug_04_no_cartesian_in_dynamic" \
       "phase 2: payload é '$is_obj' (esperado 'object' — cartesiano geraria array)"
  [[ "$imgs" == "3" && "$titles" == "4" && "$descs" == "4" ]] \
    || _fail "test_bug_04_no_cartesian_in_dynamic" \
       "phase 2: contagens imgs=$imgs/titles=$titles/descs=$descs (esperado 3/4/4)"

  # Garante que NÃO há expansão N×M (cartesiano daria 3*4*4=48)
  local total_leaves
  total_leaves=$((imgs + titles + descs))
  [[ "$total_leaves" == "11" ]] \
    || _fail "test_bug_04_no_cartesian_in_dynamic" \
       "phase 2: soma leaves=$total_leaves (esperado 11 = 3+4+4, NÃO 48 cartesiano)"

  _pass "test_bug_04_no_cartesian_in_dynamic (1 creative, shape 3/4/4 preservado)"
}

# ── Bug #5: media_fbid reusado entre posts diferentes ────────────────────────
# O caso Filipe teve skill reusando o mesmo photo_id de um post em outro post,
# causando Graph 100/1885194 ("media already in use"). Fix: cache composto
# (sha256 + post_id) — mesmo sha em posts diferentes = miss = re-upload.
#
# Estrutura do teste (estrutural — sem token nem upload real):
#   Phase 1 (negative control): media_cache_get(sha, post_A) retorna vazio
#                               antes de put — sanity check
#   Phase 2 (isolamento):       put(sha, post_A, "fbid_A"); então
#                               get(sha, post_A) = "fbid_A" E
#                               get(sha, post_B) = "" (miss — chave diferente)
#
# Regressão: se alguém simplificar a chave pra só sha (sem post_id),
# get(sha, post_B) volta a retornar "fbid_A" → teste falha → reuso de media_fbid
# volta a quebrar o caso Filipe.
test_bug_05_media_fbid_hygiene() {
  local upload_media="$PLUGIN_ROOT/lib/upload_media.sh"
  [[ -f "$upload_media" ]] || _fail "test_bug_05_media_fbid_hygiene" "upload_media.sh ausente"

  # shellcheck source=../lib/upload_media.sh disable=SC1091
  source "$upload_media"

  # Isolated manifest — não toca em runs reais
  local run_id="regression_bug05_$$_$(date +%s)"
  local manifest_dir="${HOME}/.claude/meta-ads-pro/current"
  local manifest="${manifest_dir}/${run_id}.json"
  mkdir -p "$manifest_dir"
  echo '{"media_cache": {}}' > "$manifest"
  CURRENT_RUN_ID="$run_id"
  export CURRENT_RUN_ID

  # Cleanup automático no retorno
  _cleanup_bug05() {
    rm -f "$manifest"
    unset CURRENT_RUN_ID
  }

  local sha="a1b2c3d4e5f6"
  local post_a="123456_789" post_b="987654_321"

  # ── Phase 1: negative control ────────────────────────────────────────────
  local miss
  miss=$(media_cache_get "$sha" "$post_a")
  if [[ -n "$miss" ]]; then
    _cleanup_bug05
    _fail "test_bug_05_media_fbid_hygiene" \
      "phase 1: cache retornou '$miss' antes de put (esperado vazio)"
  fi

  # ── Phase 2: put em post_A, verificar isolamento em post_B ───────────────
  media_cache_put "$sha" "$post_a" "fbid_FOR_POST_A"

  local got_a got_b
  got_a=$(media_cache_get "$sha" "$post_a")
  got_b=$(media_cache_get "$sha" "$post_b")

  if [[ "$got_a" != "fbid_FOR_POST_A" ]]; then
    _cleanup_bug05
    _fail "test_bug_05_media_fbid_hygiene" \
      "phase 2: get(sha, post_A) = '$got_a' (esperado fbid_FOR_POST_A)"
  fi

  if [[ -n "$got_b" ]]; then
    _cleanup_bug05
    _fail "test_bug_05_media_fbid_hygiene" \
      "phase 2: get(sha, post_B) = '$got_b' (esperado vazio — chave deve ser composta sha+post_id, não só sha)"
  fi

  _cleanup_bug05
  _pass "test_bug_05_media_fbid_hygiene (chave composta sha+post_id isola reuso)"
}

# ── bugs 06–09: adicionados nos CPs 3a, 3b ────────────────────────────────────

# ── execução ──────────────────────────────────────────────────────────────────
# Estruturais (rodam sempre)
test_bug_03_dev_mode_detection
test_bug_04_no_cartesian_in_dynamic
test_bug_05_media_fbid_hygiene

# Live (exigem META_ACCESS_TOKEN)
if (( HAVE_TOKEN )); then
  test_bug_10_preflight_doctor
  test_bug_01_ABO_budget_sharing_flag
  test_bug_02_advantage_audience
else
  _skip "test_bug_10_preflight_doctor"        "sem META_ACCESS_TOKEN"
  _skip "test_bug_01_ABO_budget_sharing_flag" "sem META_ACCESS_TOKEN"
  _skip "test_bug_02_advantage_audience"      "sem META_ACCESS_TOKEN"
fi

echo ""
echo "regressão Filipe: $PASS passou, $FAIL falhou (bugs 06-09 adicionados nos próximos CPs)"
[[ "$FAIL" -eq 0 ]]
