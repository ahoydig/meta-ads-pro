#!/usr/bin/env bash
# preflight.sh — 10 checks do doctor (meta-ads-doctor)
# Cada check retorna 0 (ok) / 1 (warn) / 2 (bloqueia)
# e ecoa mensagem formatada no stdout.

set -euo pipefail

# shellcheck source=/dev/null
# Fallback ${BASH_SOURCE[0]:-$0} cobre shell interativo bash 3.2 onde BASH_SOURCE[0]
# pode estar unset sob `set -u`. Fix pro bug descoberto no smoke DRY_RUN v1.0.0.
source "$(dirname "${BASH_SOURCE[0]:-$0}")/graph_api.sh"

# ─── check 1: token válido ─────────────────────────────────────────────────
check_token_valid() {
  local r
  if r=$(graph_api GET "me?fields=id,name" 2>/dev/null); then
    echo "✓ Token válido ($(echo "$r" | jq -r .name))"
  else
    echo "✗ Token inválido — rode /meta-ads-setup"
    return 2
  fi
}

# ─── check 2: expiração do token ───────────────────────────────────────────
check_token_expiration() {
  local token="${META_ACCESS_TOKEN:?}"
  local r
  r=$(curl -s "https://graph.facebook.com/v25.0/debug_token?input_token=$token&access_token=$token")
  local exp
  exp=$(echo "$r" | jq -r '.data.expires_at // 0')
  if [[ "$exp" == "0" ]]; then
    echo "✓ Token não expira"
  else
    local now days
    now=$(date +%s)
    days=$(( (exp - now) / 86400 ))
    if (( days < 7 )); then
      echo "⚠ Token expira em $days dias — regenere"
      return 1
    fi
    echo "✓ Token expira em $days dias"
  fi
}

# ─── check 3: scopes necessários ───────────────────────────────────────────
check_scopes() {
  local token="${META_ACCESS_TOKEN:?}"
  local r
  r=$(curl -s "https://graph.facebook.com/v25.0/debug_token?input_token=$token&access_token=$token")
  local missing=()
  local scopes_required=("ads_management" "ads_read" "business_management" "leads_retrieval" "pages_manage_ads")
  for s in "${scopes_required[@]}"; do
    if ! echo "$r" | jq -e ".data.scopes | index(\"$s\")" >/dev/null 2>&1; then
      missing+=("$s")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "✗ Scopes faltando: ${missing[*]}"
    return 2
  fi
  echo "✓ Scopes: 5/5 necessários"
}

# ─── check 4: app mode (dev vs live) ───────────────────────────────────────
check_app_mode() {
  local account="${AD_ACCOUNT_ID:?}"
  local page_id="${PAGE_ID:?}"
  local test_name
  test_name="_DOCTOR_TEST_$(date +%s)"
  local body
  body=$(jq -nc --arg name "$test_name" --arg pid "$page_id" '{
    name: $name,
    object_story_spec: {
      page_id: $pid,
      link_data: {message:"doctor test",link:"https://www.facebook.com"}
    },
    status: "PAUSED"
  }')

  local tmpfile
  tmpfile=$(mktemp)
  local exit_code=0
  GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$account/adcreatives" "$body" \
    > "$tmpfile" 2>/dev/null || exit_code=$?

  local response
  response=$(cat "$tmpfile")
  rm -f "$tmpfile"

  local err_subcode creative_id
  err_subcode=$(echo "$response" | jq -r '.error.error_subcode // empty' 2>/dev/null || true)
  creative_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null || true)

  if [[ "$err_subcode" == "1885183" ]]; then
    echo "⚠ App em dev mode — fallback_dark_post=true ativado"
    export FALLBACK_DARK_POST=true
    return 1
  fi

  if [[ -n "$creative_id" && "$creative_id" != "null" ]]; then
    graph_api DELETE "$creative_id" >/dev/null 2>&1 || true
    echo "✓ App em LIVE mode (criativos diretos liberados)"
    export FALLBACK_DARK_POST=false
    return 0
  fi

  echo "? App mode inconclusivo — response: $(echo "$response" | head -c 200)" >&2
  return 1
}

# ─── check 5: rate limit BUC ───────────────────────────────────────────────
check_rate_limit_buc() {
  local account="${AD_ACCOUNT_ID:?}"
  local token="${META_ACCESS_TOKEN:?}"
  local header
  header=$(curl -sI "https://graph.facebook.com/v25.0/$account?fields=id&access_token=$token" \
    | grep -i "x-business-use-case-usage" || true)
  [[ -z "$header" ]] && { echo "✓ Rate limit: baixo"; return 0; }

  local wait_min
  wait_min=$(echo "$header" | python3 -c "
import sys, re
h = sys.stdin.read()
m = re.search(r'\"estimated_time_to_regain_access\":(\d+)', h)
print(m.group(1) if m else '0')
")
  if (( wait_min > 0 )); then
    echo "✗ Rate limit bloqueado — aguarde $wait_min min"
    return 2
  fi
  echo "✓ Rate limit: ok"
}

# ─── check 6: ad account ativo ─────────────────────────────────────────────
check_ad_account_active() {
  local account="${AD_ACCOUNT_ID:?}"
  local r
  r=$(graph_api GET "$account?fields=account_status,currency,timezone_name")
  local acct_status
  acct_status=$(echo "$r" | jq -r .account_status)
  if [[ "$acct_status" != "1" ]]; then
    echo "✗ Ad account não ativo (status=$acct_status)"
    return 2
  fi
  echo "✓ Ad account ACTIVE ($(echo "$r" | jq -r .currency), $(echo "$r" | jq -r .timezone_name))"
}

# ─── check 7: page token disponível ────────────────────────────────────────
check_page_token() {
  local page_id="${PAGE_ID:?}"
  local r
  r=$(graph_api GET "$page_id?fields=access_token,name" 2>/dev/null || true)
  local len
  len=$(echo "$r" | jq -r '.access_token // "" | length')
  if (( len < 100 )); then
    echo "⚠ Page token não disponível"
    return 1
  fi
  echo "✓ Page token: $len chars ($(echo "$r" | jq -r .name))"
}

# ─── check 8: pixel configurado ────────────────────────────────────────────
check_pixel() {
  local account="${AD_ACCOUNT_ID:?}"
  local r
  r=$(graph_api GET "$account/adspixels?fields=name,last_fired_time&limit=5")
  local count
  count=$(echo "$r" | jq '.data | length')
  if (( count == 0 )); then
    echo "⚠ Sem pixels (ok se só usar Lead Form/WA)"
    return 1
  fi
  echo "✓ Pixels: $count encontrados"
}

# ─── check 9: CLAUDE.md config ─────────────────────────────────────────────
check_claude_md_config() {
  local md="${1:-CLAUDE.md}"
  [[ -f "$md" ]] || { echo "✗ CLAUDE.md não encontrado — rode /meta-ads-setup"; return 2; }
  local required=("ad_account_id" "page_id" "nomenclatura_style")
  for f in "${required[@]}"; do
    if ! grep -q "^$f:" "$md"; then
      echo "✗ Campo '$f' faltando em $md"
      return 2
    fi
  done
  echo "✓ CLAUDE.md config válido"
}

# ─── check 10: learnings pendentes ─────────────────────────────────────────
check_learnings() {
  local file="${HOME}/.claude/meta-ads-pro/learnings/unknown_errors.jsonl"
  [[ -f "$file" ]] || { echo "✓ Sem learnings pendentes"; return 0; }
  local count
  count=$(jq -rs '[.[] | select(.confirmed_by_human == false)] | length' "$file" 2>/dev/null || echo 0)
  if (( count > 0 )); then
    echo "⚠ $count learnings pendentes — rode /meta-ads-doctor --review-learnings"
    return 1
  fi
  echo "✓ Sem learnings pendentes"
}

# ─── runner completo: roda todos os 10 checks ──────────────────────────────
run_preflight() {
  local silent="${1:-0}"
  local max_severity=0
  local results=()

  _run_check() {
    local fn="$1"
    local out exit_code
    exit_code=0
    out=$("$fn" 2>&1) || exit_code=$?
    results+=("$out")
    if (( exit_code > max_severity )); then
      max_severity=$exit_code
    fi
    if [[ "$silent" == "0" ]] || (( exit_code > 0 )); then
      echo "$out"
    fi
  }

  _run_check check_token_valid
  _run_check check_token_expiration
  _run_check check_scopes
  _run_check check_rate_limit_buc
  _run_check check_ad_account_active
  _run_check check_page_token
  _run_check check_pixel
  _run_check check_claude_md_config
  _run_check check_learnings
  # check_app_mode é separado (faz chamada real à API — caro)
  # Rodado via --full-check ou explicitamente

  return $max_severity
}
