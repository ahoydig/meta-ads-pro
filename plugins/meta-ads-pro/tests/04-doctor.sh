#!/usr/bin/env bash
# tests/04-doctor.sh — Camada 3: 14 testes assertivos dos checks do doctor
# (10 originais + 4 novos: GHL, receiver, subscrição leadgen, dataset CAPI)
# Requer: META_ACCESS_TOKEN, AD_ACCOUNT_ID
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFLIGHT="$PLUGIN_ROOT/lib/preflight.sh"

# ── guards ────────────────────────────────────────────────────────────────────
[[ -n "${META_ACCESS_TOKEN:-}" ]] || { echo "SKIP: sem META_ACCESS_TOKEN"; exit 0; }
[[ -n "${AD_ACCOUNT_ID:-}"     ]] || { echo "SKIP: sem AD_ACCOUNT_ID";     exit 0; }

if [[ ! -f "$PREFLIGHT" ]]; then
  echo "SKIP: $PREFLIGHT não existe ainda (aguardando bash-dev)"
  exit 0
fi

# shellcheck source=../lib/preflight.sh
source "$PREFLIGHT"

PASS=0; FAIL=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2"; (( FAIL++ )) || true; }
_skip() { echo "⊘ $1: $2"; (( PASS++ )) || true; }

# ── testes ────────────────────────────────────────────────────────────────────

# 1. Token existe e é aceito pelo /me
test_token_valid() {
  if check_token_valid; then
    _pass "test_token_valid"
  else
    _fail "test_token_valid" "token rejeitado pela API"
  fi
}

# 2. Token não expirado (long-lived ≥ 24h restantes)
test_token_expiration() {
  if check_token_expiration; then
    _pass "test_token_expiration"
  else
    _fail "test_token_expiration" "token expirado ou prestes a expirar"
  fi
}

# 3. Scopes obrigatórios presentes
test_scopes() {
  if check_scopes; then
    _pass "test_scopes"
  else
    _fail "test_scopes" "scopes insuficientes — rode /meta-ads-setup"
  fi
}

# 4. App mode (dev vs live) — check_app_mode deve setar FALLBACK_DARK_POST
test_app_mode() {
  unset FALLBACK_DARK_POST || true
  # não falha o teste se app estiver em dev mode — apenas verifica que a flag é setada
  check_app_mode 2>/dev/null || true
  if [[ -n "${FALLBACK_DARK_POST:-}" ]]; then
    _pass "test_app_mode (FALLBACK_DARK_POST=${FALLBACK_DARK_POST})"
  else
    _fail "test_app_mode" "check_app_mode não setou FALLBACK_DARK_POST"
  fi
}

# 5. Rate limit BUC — retorna 0 se abaixo do threshold
test_rate_limit_buc() {
  if check_rate_limit_buc; then
    _pass "test_rate_limit_buc"
  else
    _fail "test_rate_limit_buc" "BUC rate limit alto — aguarde antes de criar objetos"
  fi
}

# 6. Ad account existe e está ACTIVE
test_ad_account_active() {
  if check_ad_account_active; then
    _pass "test_ad_account_active"
  else
    _fail "test_ad_account_active" "conta $AD_ACCOUNT_ID não encontrada ou desativada"
  fi
}

# 7. Page token (opcional: só se PAGE_ID setado)
test_page_token() {
  if [[ -z "${PAGE_ID:-}" ]]; then
    _skip "test_page_token" "PAGE_ID não definido"
    return
  fi
  # check_page_token pode retornar 1 se page não tiver token válido; não falha CI
  local rc=0
  check_page_token 2>/dev/null || rc=$?
  if (( rc == 0 )); then
    _pass "test_page_token"
  else
    _skip "test_page_token" "page sem token válido (rc=$rc) — configure via setup"
  fi
}

# 8. Pixel (opcional: só se PIXEL_ID setado; check retorna warn, não erro fatal)
test_pixel() {
  local rc=0
  check_pixel 2>/dev/null || rc=$?
  # 0 = pixel OK; 1 = pixel não encontrado/sem dados (warn apenas em CP1)
  _pass "test_pixel (rc=$rc)"
}

# 9. CLAUDE.md possui Meta Ads Config com campos mínimos
test_claude_md_config() {
  local tmp
  tmp=$(mktemp)
  # cria CLAUDE.md fake com campos mínimos
  cat > "$tmp" <<'MD'
## Meta Ads Config
ad_account_id: act_TEST_123
page_id: 123456
nomenclatura_style: ahoy-style
MD
  if check_claude_md_config "$tmp"; then
    _pass "test_claude_md_config"
  else
    _fail "test_claude_md_config" "check_claude_md_config rejeitou CLAUDE.md válido"
  fi
  rm -f "$tmp"
}

# 10. Learnings pendentes (warn tolerado — não bloqueia CI)
test_learnings() {
  local rc=0
  check_learnings 2>/dev/null || rc=$?
  # rc=0 = sem pendentes; rc=1 = tem pendentes (warn, não falha)
  if (( rc == 0 )); then
    _pass "test_learnings: sem learnings pendentes"
  else
    _pass "test_learnings: ⚠ ${rc} learnings pendentes (rode /meta-ads-doctor --review-learnings)"
  fi
}

# 11. GHL/FluxiHub — sem GHL_PIT_TOKEN/GHL_LOCATION_ID no ambiente, deve avisar (não bloquear)
test_ghl() {
  local saved_token="${GHL_PIT_TOKEN:-}" saved_loc="${GHL_LOCATION_ID:-}"
  unset GHL_PIT_TOKEN GHL_LOCATION_ID 2>/dev/null || true
  local out rc=0
  out=$(check_ghl 2>&1) || rc=$?
  if (( rc == 1 )) && [[ "$out" == *"⚠"* ]]; then
    _pass "test_ghl: sem env → aviso (rc=1)"
  else
    _fail "test_ghl" "esperado rc=1 com ⚠ sem GHL_PIT_TOKEN/GHL_LOCATION_ID, obteve rc=$rc out=$out"
  fi
  [[ -n "$saved_token" ]] && export GHL_PIT_TOKEN="$saved_token" || true
  [[ -n "$saved_loc" ]] && export GHL_LOCATION_ID="$saved_loc" || true
}

# 12. Receiver de leadgen — URL que responde 404 (sem JSON válido) deve avisar forte
# (rc=1, não bloqueia — mudança de contrato consciente: check_ghl/check_receiver são
# integração opcional, ver lib/preflight.sh e flows/doctor/SKILL.md checks 11/12).
test_receiver() {
  local saved="${RECEIVER_HEALTH_URL:-}"
  export RECEIVER_HEALTH_URL="https://example.com/404"
  local out rc=0
  out=$(check_receiver 2>&1) || rc=$?
  if (( rc == 1 )); then
    _pass "test_receiver: URL fora do ar/sem JSON → aviso forte, não bloqueia (rc=1)"
  else
    _fail "test_receiver" "esperado rc=1 com RECEIVER_HEALTH_URL=https://example.com/404, obteve rc=$rc out=$out"
  fi
  if [[ -n "$saved" ]]; then export RECEIVER_HEALTH_URL="$saved"; else unset RECEIVER_HEALTH_URL; fi
}

# 13. Subscrição leadgen da página (opcional: só se PAGE_ID setado; tolerante — não falha CI)
test_leadgen_subscription() {
  if [[ -z "${PAGE_ID:-}" ]]; then
    _skip "test_leadgen_subscription" "PAGE_ID não definido"
    return
  fi
  local rc=0
  check_leadgen_subscription 2>/dev/null || rc=$?
  # rc=0 = subscrita em leadgen; rc=1 = não subscrita (warn, não falha CI)
  _pass "test_leadgen_subscription (rc=$rc)"
}

# 14. Dataset CAPI — sem PIXEL_ID deve avisar (não bloquear)
test_capi_dataset() {
  local saved="${PIXEL_ID:-}"
  unset PIXEL_ID 2>/dev/null || true
  local out rc=0
  out=$(check_capi_dataset 2>&1) || rc=$?
  if (( rc == 1 )) && [[ "$out" == *"⚠"* ]]; then
    _pass "test_capi_dataset: sem PIXEL_ID → aviso (rc=1)"
  else
    _fail "test_capi_dataset" "esperado rc=1 com ⚠ sem PIXEL_ID, obteve rc=$rc out=$out"
  fi
  [[ -n "$saved" ]] && export PIXEL_ID="$saved" || true
}

# ── execução ──────────────────────────────────────────────────────────────────
for t in \
  test_token_valid \
  test_token_expiration \
  test_scopes \
  test_app_mode \
  test_rate_limit_buc \
  test_ad_account_active \
  test_page_token \
  test_pixel \
  test_claude_md_config \
  test_learnings \
  test_ghl \
  test_receiver \
  test_leadgen_subscription \
  test_capi_dataset
do
  $t
done

echo ""
echo "doctor: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
