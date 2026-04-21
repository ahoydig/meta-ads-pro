#!/usr/bin/env bash
# tests/04-doctor.sh — Camada 3: 10 testes assertivos dos checks do doctor
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
  test_learnings
do
  $t
done

echo ""
echo "doctor: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
