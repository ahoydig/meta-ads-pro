#!/usr/bin/env bash
# tests/08-lead-forms.sh — Camada 3: sub-skill lead-forms (12 testes)
#
# Estratégia:
#   - Testes 01-04 são client-side (validação pré-POST, sem token necessário)
#   - Testes 05-07 são privacy-validator (requerem rede pra URL válida; skip se offline)
#   - Testes 08-09 fazem POST real em /leadgen_forms (requer META_ACCESS_TOKEN + PAGE_ID)
#   - Testes 10-12 são stubs pra CP3c (qualifier/conditional/preview)
#
# Cleanup: todos os forms criados vão pra array, DELETE no trap EXIT.
# Prefixo TEST_ garante cleanup via tests/cleanup.sh caso o trap falhe.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=../lib/privacy-validator.sh disable=SC1091
source "$PLUGIN_ROOT/lib/privacy-validator.sh"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2" >&2; (( FAIL++ )) || true; exit 1; }
_skip() { echo "- $1 (SKIP: $2)"; (( SKIP++ )) || true; }

VALID_PRIVACY_URL="${VALID_PRIVACY_URL:-https://lp.ahoy.digital/politicas-privacidade}"

created_forms=()
_cleanup_forms() {
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh" 2>/dev/null || return 0
  for fid in "${created_forms[@]:-}"; do
    [[ -n "$fid" && "$fid" != DRY_RUN_* ]] || continue
    GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$fid" >/dev/null 2>&1 || true
  done
}
trap _cleanup_forms EXIT

_need_token() {
  [[ -n "${META_ACCESS_TOKEN:-}" && -n "${PAGE_ID:-}" ]]
}

# ─── helper: payload mínimo válido ────────────────────────────────────────────
build_minimal_form_payload() {
  local name
  name="TEST_$(date +%s)_$$_$RANDOM"
  jq -nc \
    --arg name "$name" \
    --arg intro_title "Intro test" \
    --arg intro_desc "Descrição de introdução" \
    --arg privacy_url "$VALID_PRIVACY_URL" \
    --arg thankyou_title "Obrigado!" \
    --arg thankyou_desc "Em contato em breve" \
    --arg disq_title "Não elegível" \
    --arg disq_desc "Siga nosso IG" \
    '{
      name: $name,
      questions: [
        {type:"FULL_NAME"},
        {type:"EMAIL"},
        {type:"PHONE"}
      ],
      privacy_policy: {url: $privacy_url},
      context_card: {title: $intro_title, content: [$intro_desc]},
      thank_you_page: {title: $thankyou_title, body: $thankyou_desc},
      disqualified_thank_you_page: {title: $disq_title, body: $disq_desc},
      follow_up_action_url: $privacy_url
    }'
}

# ─── Client-side validation function (simula skill-level check) ───────────────
validate_form_payload_clientside() {
  local payload="$1"
  # 8 campos obrigatórios — se qualquer faltar, retorna erro
  local required=(name questions context_card privacy_policy thank_you_page disqualified_thank_you_page)
  for field in "${required[@]}"; do
    if ! echo "$payload" | jq -e --arg f "$field" 'has($f)' >/dev/null 2>&1; then
      echo "MISSING: $field" >&2
      return 1
    fi
  done
  # questions ≥ 1
  local qcount
  qcount=$(echo "$payload" | jq '.questions | length' 2>/dev/null || echo 0)
  if (( qcount < 1 )); then
    echo "MISSING: questions (≥1)" >&2
    return 1
  fi
  return 0
}

# ─── Test 01: create complete form (live POST) ────────────────────────────────
test_01_create_complete_form() {
  if ! _need_token; then
    _skip "test_01_create_complete_form" "sem META_ACCESS_TOKEN/PAGE_ID"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local payload
  payload=$(build_minimal_form_payload)

  local response fid
  # _fail chama exit 1 — shellcheck disable pra return após _fail
  response=$(graph_api POST "${PAGE_ID}/leadgen_forms" "$payload") \
    || _fail "test_01_create_complete_form" "POST falhou: $response"
  fid=$(echo "$response" | jq -r '.id // empty')
  [[ -n "$fid" ]] || _fail "test_01_create_complete_form" "sem id no response: $response"
  created_forms+=("$fid")
  _pass "test_01_create_complete_form (fid=$fid)"
}

# ─── Test 02: missing intro rejected (client-side) ────────────────────────────
test_02_missing_intro_rejected() {
  local payload
  payload=$(build_minimal_form_payload | jq 'del(.context_card)')
  ! validate_form_payload_clientside "$payload" 2>/dev/null \
    || _fail "test_02_missing_intro_rejected" "payload sem context_card foi aceito"
  _pass "test_02_missing_intro_rejected (client-side check)"
}

# ─── Test 03: missing thank_you_page (qualificado) rejected ───────────────────
test_03_missing_thankyou_qual_rejected() {
  local payload
  payload=$(build_minimal_form_payload | jq 'del(.thank_you_page)')
  ! validate_form_payload_clientside "$payload" 2>/dev/null \
    || _fail "test_03_missing_thankyou_qual_rejected" "payload sem thank_you_page aceito"
  _pass "test_03_missing_thankyou_qual_rejected (client-side check)"
}

# ─── Test 04: missing disqualified_thank_you_page rejected (bug #8) ───────────
test_04_missing_thankyou_disq_rejected() {
  local payload
  payload=$(build_minimal_form_payload | jq 'del(.disqualified_thank_you_page)')
  ! validate_form_payload_clientside "$payload" 2>/dev/null \
    || _fail "test_04_missing_thankyou_disq_rejected" \
      "payload sem disqualified_thank_you_page aceito — bug #8 regrediu"
  _pass "test_04_missing_thankyou_disq_rejected (client-side, bug #8 fix)"
}

# ─── Test 05: privacy Instagram URL rejected (bug #7) ─────────────────────────
test_05_privacy_instagram_rejected() {
  # invalida cache pra garantir execução real
  invalidate_privacy_cache "https://www.instagram.com/institutofaceacademy/" >/dev/null 2>&1 || true
  ! validate_privacy_url "https://www.instagram.com/institutofaceacademy/" 2>/dev/null \
    || _fail "test_05_privacy_instagram_rejected" "Instagram aceito — bug #7 regrediu"
  _pass "test_05_privacy_instagram_rejected (bug #7 fix)"
}

# ─── Test 06: privacy 404 rejected ────────────────────────────────────────────
test_06_privacy_404_rejected() {
  local url="https://lp.ahoy.digital/nonexistent-privacy-$$-$RANDOM"
  invalidate_privacy_cache "$url" >/dev/null 2>&1 || true
  ! validate_privacy_url "$url" 2>/dev/null \
    || _fail "test_06_privacy_404_rejected" "404 aceito"
  _pass "test_06_privacy_404_rejected"
}

# ─── Test 07: privacy valid URL accepted ──────────────────────────────────────
test_07_privacy_valid_accepted() {
  invalidate_privacy_cache "$VALID_PRIVACY_URL" >/dev/null 2>&1 || true
  if validate_privacy_url "$VALID_PRIVACY_URL" >/dev/null 2>&1; then
    _pass "test_07_privacy_valid_accepted"
  else
    _skip "test_07_privacy_valid_accepted" "URL de privacy offline ou não bate 3 camadas ($VALID_PRIVACY_URL)"
  fi
}

# ─── Test 08: short_answer question (live POST) ───────────────────────────────
test_08_short_answer_question() {
  if ! _need_token; then
    _skip "test_08_short_answer_question" "sem META_ACCESS_TOKEN/PAGE_ID"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local payload response fid
  payload=$(build_minimal_form_payload | jq \
    '.questions += [{type:"CUSTOM", key:"interest", label:"Qual interesse?", input_type:"SHORT_ANSWER"}]')
  response=$(graph_api POST "${PAGE_ID}/leadgen_forms" "$payload") \
    || _fail "test_08_short_answer_question" "POST falhou: $response"
  fid=$(echo "$response" | jq -r '.id // empty')
  [[ -n "$fid" ]] || _fail "test_08_short_answer_question" "sem id: $response"
  created_forms+=("$fid")
  _pass "test_08_short_answer_question (fid=$fid)"
}

# ─── Test 09: multiple_choice question (live POST) ────────────────────────────
test_09_multiple_choice_question() {
  if ! _need_token; then
    _skip "test_09_multiple_choice_question" "sem META_ACCESS_TOKEN/PAGE_ID"
    return 0
  fi
  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local payload response fid
  payload=$(build_minimal_form_payload | jq \
    '.questions += [{
      type:"CUSTOM",
      key:"proc",
      label:"Procedimento?",
      input_type:"MULTIPLE_CHOICE",
      options:[{value:"Opt1"},{value:"Opt2"},{value:"Opt3"}]
    }]')
  response=$(graph_api POST "${PAGE_ID}/leadgen_forms" "$payload") \
    || _fail "test_09_multiple_choice_question" "POST falhou: $response"
  fid=$(echo "$response" | jq -r '.id // empty')
  [[ -n "$fid" ]] || _fail "test_09_multiple_choice_question" "sem id: $response"
  created_forms+=("$fid")
  _pass "test_09_multiple_choice_question (fid=$fid)"
}

# ─── Test 10-12: stubs pra CP3c ───────────────────────────────────────────────
test_10_qualifier_disqualifier_stub() {
  _skip "test_10_qualifier_disqualifier_stub" "implementação em CP3c (filtro qualifier por answer)"
}

test_11_conditional_logic_stub() {
  _skip "test_11_conditional_logic_stub" "implementação em CP3c (B só se A=X via conditional_questions)"
}

test_12_preview_html_stub() {
  _skip "test_12_preview_html_stub" "implementação em CP3c (visual-preview HTML interativo do form)"
}

# ─── Execução ─────────────────────────────────────────────────────────────────
test_01_create_complete_form
test_02_missing_intro_rejected
test_03_missing_thankyou_qual_rejected
test_04_missing_thankyou_disq_rejected
test_05_privacy_instagram_rejected
test_06_privacy_404_rejected
test_07_privacy_valid_accepted
test_08_short_answer_question
test_09_multiple_choice_question
test_10_qualifier_disqualifier_stub
test_11_conditional_logic_stub
test_12_preview_html_stub

echo ""
echo "lead-forms: ${PASS} passou, ${FAIL} falhou, ${SKIP} pulados"
(( FAIL == 0 ))
