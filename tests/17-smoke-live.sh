#!/usr/bin/env bash
# tests/17-smoke-live.sh — Camada 6: smoke live em conta Meta real (CP4, Task 4.1.1)
#
# ⚠  GERA GASTO REAL. Só executa com --confirm e env vars setadas.
#
# Fluxo:
#   1.  valida --confirm + env vars + confirma via TTY (se interativo)
#   2.  preflight mínimo (token / account active / rate limit)
#   3.  manifest_init
#   4.  cria lead form mínimo em /{page}/leadgen_forms
#   5.  cria campanha OUTCOME_LEADS (PAUSED)
#   6.  cria ad set Lead Form (advantage_audience=0, daily_budget=518)
#   7.  ATIVA campanha + adset
#   8.  monitora /insights a cada 30min por 3h OU até bater hard limit R$10
#   9.  pausa ao terminar, coleta effective_status + review_status
#   10. rollback_run (trap EXIT também dispara se algo escapar)
#
# Configuração (env):
#   META_ACCESS_TOKEN  — obrigatório
#   AD_ACCOUNT_ID      — obrigatório (ex.: act_763408067802379)
#   PAGE_ID            — obrigatório
#   SMOKE_HARD_LIMIT_CENTS    — default 1000 (R$10)
#   SMOKE_DAILY_BUDGET_CENTS  — default 518  (R$5,18 — mínimo conta Flávio)
#   SMOKE_MONITOR_DURATION    — default 10800 (3h, em segundos)
#   SMOKE_POLL_INTERVAL       — default 1800 (30min, em segundos)
#   SMOKE_PRIVACY_URL         — default https://lp.ahoy.digital/politicas-privacidade
#
# Segurança:
#   - Zero vazamento de token: nunca ecoa $META_ACCESS_TOKEN, nunca roda set -x.
#   - graph_api wrapper usa access_token em body/query e loga só response body
#     em caso de erro (body não contém token).
#   - trap EXIT garante pause+rollback mesmo em SIGINT/SIGTERM/crash.
#
# Bash 3.2 portable. shellcheck clean (disables documentados).

# -e off propositalmente — cada POST crítico tem guard explícito (|| { exit 1 }).
# -u/-o pipefail mantidos pra detectar var não setada + falha em pipes.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ─── flags ────────────────────────────────────────────────────────────────────
CONFIRM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRM=1; shift ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0 ;;
    *) shift ;;
  esac
done

if (( CONFIRM != 1 )); then
  echo "SKIP: 17-smoke-live.sh requer --confirm explícito (gera gasto real em conta Meta)"
  exit 0
fi

# ─── env obrigatórias ────────────────────────────────────────────────────────
if [[ -z "${META_ACCESS_TOKEN:-}" || -z "${AD_ACCOUNT_ID:-}" || -z "${PAGE_ID:-}" ]]; then
  echo "SKIP: exige META_ACCESS_TOKEN + AD_ACCOUNT_ID + PAGE_ID"
  exit 0
fi

# ─── config ───────────────────────────────────────────────────────────────────
HARD_LIMIT_CENTS="${SMOKE_HARD_LIMIT_CENTS:-1000}"
DAILY_BUDGET_CENTS="${SMOKE_DAILY_BUDGET_CENTS:-518}"
MONITOR_DURATION_SEC="${SMOKE_MONITOR_DURATION:-10800}"
POLL_INTERVAL_SEC="${SMOKE_POLL_INTERVAL:-1800}"
PRIVACY_URL="${SMOKE_PRIVACY_URL:-https://lp.ahoy.digital/politicas-privacidade}"

# ─── formatação BRL (centavos → R$ X,YZ) ─────────────────────────────────────
fmt_brl() {
  awk -v c="$1" 'BEGIN{printf "R$ %d,%02d", c/100, c%100}'
}

# ─── libs ─────────────────────────────────────────────────────────────────────
# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"
# shellcheck source=../lib/rollback.sh disable=SC1091
source "$PLUGIN_ROOT/lib/rollback.sh"
# shellcheck source=../lib/preflight.sh disable=SC1091
source "$PLUGIN_ROOT/lib/preflight.sh"

# ─── state ────────────────────────────────────────────────────────────────────
run_id="smoke-live-$(date +%s)"
export CURRENT_RUN_ID="$run_id"
camp_id=""
adset_id=""
form_id=""
hard_limit_hit=0
impressions_final=0
spend_cents_final=0
effective_status_final="unknown"
review_status_final="unknown"

# ─── cleanup trap: pausa + rollback ───────────────────────────────────────────
# shellcheck disable=SC2329  # invocado via trap
cleanup() {
  local rc=$?
  # Nunca ecoa token. Nunca set -x aqui.
  set +e
  trap - EXIT INT TERM

  # Pausa defensiva (evita continuar gastando durante rollback)
  if [[ -n "$adset_id" ]]; then
    GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$adset_id" '{"status":"PAUSED"}' \
      >/dev/null 2>&1 || true
  fi
  if [[ -n "$camp_id" ]]; then
    GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$camp_id" '{"status":"PAUSED"}' \
      >/dev/null 2>&1 || true
  fi

  # Rollback se manifest ainda existe no current/
  local manifest_file
  manifest_file=$(manifest_path "$run_id" 2>/dev/null || true)
  if [[ -n "$manifest_file" && -f "$manifest_file" ]]; then
    echo "→ [cleanup] rollback $run_id..."
    rollback_run "$run_id" 2>&1 | grep -vE 'access_token' || true
  fi

  exit "$rc"
}
trap cleanup EXIT INT TERM

# ─── banner ───────────────────────────────────────────────────────────────────
echo "╔════════════════════════════════════════════════╗"
echo "║  SMOKE LIVE — meta-ads-pro v1.0.0 (CP4)        ║"
echo "╠════════════════════════════════════════════════╣"
printf "║  Conta:         %-31s║\n" "$AD_ACCOUNT_ID"
printf "║  Page:          %-31s║\n" "$PAGE_ID"
printf "║  Daily budget:  %-31s║\n" "$(fmt_brl "$DAILY_BUDGET_CENTS")/dia"
printf "║  Hard limit:    %-31s║\n" "$(fmt_brl "$HARD_LIMIT_CENTS")"
printf "║  Duração:       %-31s║\n" "$((MONITOR_DURATION_SEC / 3600))h (poll $((POLL_INTERVAL_SEC / 60))min)"
printf "║  run_id:        %-31s║\n" "$run_id"
echo "╚════════════════════════════════════════════════╝"

# ─── confirmação interativa adicional (se TTY) ───────────────────────────────
if [[ -t 0 ]]; then
  printf "⚠  Isso vai gerar gasto REAL. Confirmar? [s/N] "
  read -r resp
  case "$resp" in
    s|S|sim|SIM) ;;
    *) echo "Abortado pelo usuário"; exit 1 ;;
  esac
fi

# ─── preflight mínimo (checks caros + env-specific são skipped) ───────────────
echo ""
echo "→ preflight (token / account / rate limit)..."
pf_rc=0
check_token_valid       || pf_rc=$?
check_ad_account_active || pf_rc=$?
check_rate_limit_buc    || pf_rc=$?
if (( pf_rc >= 2 )); then
  echo "✗ preflight bloqueou — abortando sem criar nada"
  exit 2
fi

# ─── 1. manifest ──────────────────────────────────────────────────────────────
echo ""
echo "→ init manifest..."
manifest_init "$run_id" "$AD_ACCOUNT_ID"
echo "✓ manifest: $(manifest_path "$run_id")"

# ─── 2. lead form mínimo ──────────────────────────────────────────────────────
echo ""
echo "→ criando lead form (_SMOKE_form)..."
form_payload=$(jq -nc --arg url "$PRIVACY_URL" '{
  name: "_SMOKE_form",
  questions: [
    {type:"FULL_NAME"},
    {type:"EMAIL"},
    {type:"PHONE"}
  ],
  privacy_policy: {url: $url},
  context_card: {
    style: "LIST_STYLE",
    title: "Workshop Claude Code",
    content: ["Inscreva-se pra receber detalhes do workshop."],
    button_text: "Continuar"
  },
  thank_you_page: {
    title: "Obrigado!",
    body: "Em breve entramos em contato.",
    button_type: "VIEW_WEBSITE",
    button_text: "Saiba mais",
    website_url: $url
  },
  disqualified_thank_you_page: {
    title: "Obrigado pelo interesse",
    body: "Siga @flavioahoy pra conteúdo sobre Claude Code.",
    button_type: "VIEW_WEBSITE",
    button_text: "Ir pro Instagram",
    website_url: "https://instagram.com/flavioahoy"
  },
  follow_up_action_url: $url
}')
form_resp=$(graph_api POST "${PAGE_ID}/leadgen_forms" "$form_payload") || {
  echo "✗ falhou criar lead form"; exit 1;
}
form_id=$(echo "$form_resp" | jq -r '.id // empty')
[[ -n "$form_id" ]] || { echo "✗ form response sem id: $form_resp"; exit 1; }
manifest_add "leadgen_form" "$form_id"
echo "✓ form: $form_id"

# ─── 3. campanha OUTCOME_LEADS (PAUSED) ───────────────────────────────────────
echo ""
echo "→ criando campanha (OUTCOME_LEADS, PAUSED)..."
camp_payload=$(jq -nc '{
  name: "_SMOKE_workshop-claude-code_leads_lp_abo",
  objective: "OUTCOME_LEADS",
  status: "PAUSED",
  special_ad_categories: [],
  buying_type: "AUCTION",
  is_skadnetwork_attribution: false
}')
camp_resp=$(graph_api POST "${AD_ACCOUNT_ID}/campaigns" "$camp_payload") || {
  echo "✗ falhou criar campanha"; exit 1;
}
camp_id=$(echo "$camp_resp" | jq -r '.id // empty')
[[ -n "$camp_id" ]] || { echo "✗ camp response sem id: $camp_resp"; exit 1; }
manifest_add "campaign" "$camp_id"
echo "✓ campanha: $camp_id"

# ─── 4. ad set Lead Form (advantage_audience=0) ──────────────────────────────
echo ""
echo "→ criando ad set (Lead Form, advantage_audience=0)..."
adset_payload=$(jq -nc \
  --arg c "$camp_id" \
  --arg pid "$PAGE_ID" \
  --argjson db "$DAILY_BUDGET_CENTS" '{
    name: "_SMOKE_adset_leadform",
    campaign_id: $c,
    status: "PAUSED",
    optimization_goal: "LEAD_GENERATION",
    billing_event: "IMPRESSIONS",
    bid_amount: 200,
    daily_budget: $db,
    destination_type: "ON_AD",
    promoted_object: {page_id: $pid},
    targeting: {
      geo_locations: {countries: ["BR"]},
      age_min: 25,
      age_max: 55,
      targeting_automation: {advantage_audience: 0}
    }
  }')
adset_resp=$(graph_api POST "${AD_ACCOUNT_ID}/adsets" "$adset_payload") || {
  echo "✗ falhou criar adset"; exit 1;
}
adset_id=$(echo "$adset_resp" | jq -r '.id // empty')
[[ -n "$adset_id" ]] || { echo "✗ adset response sem id: $adset_resp"; exit 1; }
manifest_add "adset" "$adset_id"
echo "✓ adset: $adset_id"

# ─── 5. ATIVA ─────────────────────────────────────────────────────────────────
echo ""
echo "→ ativando campanha + adset..."
graph_api POST "$camp_id"  '{"status":"ACTIVE"}' >/dev/null || {
  echo "✗ falhou ativar campanha"; exit 1;
}
graph_api POST "$adset_id" '{"status":"ACTIVE"}' >/dev/null || {
  echo "✗ falhou ativar adset"; exit 1;
}
echo "✓ ativos"
echo "  (sem ad criado — smoke valida plumbing; impressions serão 0 se não houver ad)"

# ─── 6. monitor loop ──────────────────────────────────────────────────────────
echo ""
echo "→ monitorando $((MONITOR_DURATION_SEC / 3600))h, poll a cada $((POLL_INTERVAL_SEC / 60))min..."
echo "  hard limit: $(fmt_brl "$HARD_LIMIT_CENTS")"
echo ""

start_ts=$(date +%s)
poll_count=0

while :; do
  now_ts=$(date +%s)
  elapsed=$(( now_ts - start_ts ))
  (( elapsed >= MONITOR_DURATION_SEC )) && break

  # insights — silencia resolver (monitor não deve auto-retry indefinido)
  insights=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET \
    "${camp_id}/insights?fields=spend,impressions,clicks&date_preset=today" 2>/dev/null \
    || echo '{"data":[]}')

  spend=$(echo "$insights"      | jq -r '.data[0].spend // "0"')
  impressions=$(echo "$insights" | jq -r '.data[0].impressions // "0"')
  clicks=$(echo "$insights"      | jq -r '.data[0].clicks // "0"')
  spend_cents=$(awk -v s="$spend" 'BEGIN{printf "%d", s*100 + 0.5}')

  poll_count=$(( poll_count + 1 ))
  impressions_final="$impressions"
  spend_cents_final="$spend_cents"

  printf "  [%s] poll#%-2d  spend=%s  impressions=%s  clicks=%s\n" \
    "$(date +%H:%M:%S)" "$poll_count" \
    "$(fmt_brl "$spend_cents")" "$impressions" "$clicks"

  # hard limit check
  if (( spend_cents > HARD_LIMIT_CENTS )); then
    echo ""
    echo "⚠  HARD LIMIT ($(fmt_brl "$HARD_LIMIT_CENTS")) atingido — pausando imediatamente"
    hard_limit_hit=1
    break
  fi

  # sleep em steps pequenos pra permitir SIGINT responsivo
  remaining=$POLL_INTERVAL_SEC
  while (( remaining > 0 )); do
    step=30
    (( remaining < step )) && step=$remaining
    sleep "$step"
    remaining=$(( remaining - step ))
    now_ts=$(date +%s)
    (( now_ts - start_ts >= MONITOR_DURATION_SEC )) && break
  done
done

# ─── 7. pausa + status final ──────────────────────────────────────────────────
echo ""
echo "→ pausando..."
graph_api POST "$adset_id" '{"status":"PAUSED"}' >/dev/null 2>&1 || true
graph_api POST "$camp_id"  '{"status":"PAUSED"}' >/dev/null 2>&1 || true

echo "→ coletando status final..."
status_resp=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET \
  "${camp_id}?fields=effective_status,status,configured_status" 2>/dev/null \
  || echo '{}')
effective_status_final=$(echo "$status_resp" | jq -r '.effective_status // "unknown"')

# review_status por adset (campanha não tem review_status; ad teria — sem ad aqui)
adset_status_resp=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET \
  "${adset_id}?fields=review_feedback,effective_status" 2>/dev/null \
  || echo '{}')
review_status_final=$(echo "$adset_status_resp" | jq -r '.review_feedback // "none"')

# ─── 8. assertions ────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SMOKE LIVE — RESUMO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  run_id:            %s\n" "$run_id"
printf "  polls:             %d\n" "$poll_count"
printf "  spend total:       %s\n" "$(fmt_brl "$spend_cents_final")"
printf "  impressions:       %s\n" "$impressions_final"
printf "  hard_limit_hit:    %s\n" "$hard_limit_hit"
printf "  effective_status:  %s\n" "$effective_status_final"
printf "  review_feedback:   %s\n" "$review_status_final"
echo ""

smoke_rc=0

# assertion 1: não rejeitado pela Meta
case "$effective_status_final" in
  DISAPPROVED|REJECTED|WITH_ISSUES)
    echo "✗ effective_status = $effective_status_final (rejeitado)"
    smoke_rc=1
    ;;
  PENDING_REVIEW)
    if (( hard_limit_hit == 0 )); then
      echo "✗ effective_status = PENDING_REVIEW após $((MONITOR_DURATION_SEC / 3600))h (review travou)"
      smoke_rc=1
    else
      echo "⚠ effective_status = PENDING_REVIEW (hard limit cortou antes da aprovação — aceitável)"
    fi
    ;;
  *)
    echo "✓ effective_status ok ($effective_status_final)"
    ;;
esac

# assertion 2: impressions > 0 (WARN, não falha — smoke não cria ad, então 0 é esperado)
# NOTA: se no futuro Task 4.1.1b criar ad+creative real, promover este WARN pra FAIL.
if [[ "$impressions_final" == "0" || -z "$impressions_final" ]]; then
  echo "⚠ impressions=0 (esperado pra smoke sem ad — plumbing ok)"
else
  echo "✓ impressions=$impressions_final (bônus — ad criado fora do smoke?)"
fi

# assertion 3: hard limit não foi largamente estourado
if (( spend_cents_final > HARD_LIMIT_CENTS * 2 )); then
  echo "✗ spend (${spend_cents_final}c) >2× hard limit — monitor não respondeu"
  smoke_rc=1
fi

# ─── 9. rollback (idempotente; cleanup trap também cobre) ────────────────────
echo ""
echo "→ rollback explícito..."
rollback_run "$run_id" 2>&1 | grep -vE 'access_token' || true

# Limpa IDs pra trap não re-tentar
camp_id=""
adset_id=""
form_id=""

echo ""
if (( smoke_rc == 0 )); then
  echo "✓ SMOKE LIVE PASSOU — liberado pra tag v1.0.0"
else
  echo "✗ SMOKE LIVE FALHOU — ver asserts acima"
fi

exit "$smoke_rc"
