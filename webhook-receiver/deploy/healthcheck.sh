#!/usr/bin/env bash
# healthcheck.sh — monitor do receiver de leadgen (F2.4/F5.1 do plano de fechamento).
# Roda por cron na VPS; alerta no canal do time se o receiver degradar.
#
# Detecta: serviço down · errors/no_config crescendo entre execuções · last_status de falha.
# Alerta via webhook configurável (ALERT_WEBHOOK_URL — Slack/Barba/qualquer POST JSON).
# NÃO ecoa segredos. Estado entre execuções em STATE_FILE (contadores da última corrida).
#
# Crontab sugerido (a cada 10 min):
#   */10 * * * * /opt/meta-leads/deploy/healthcheck.sh >> /var/log/meta-leads-healthcheck.log 2>&1
#
# Env (de /opt/meta-leads/.env ou do ambiente do cron):
#   HEALTH_URL         (default http://127.0.0.1:8811/meta-leads/health)
#   ALERT_WEBHOOK_URL  (obrigatório pra alertar; sem ele só loga)
#   STATE_FILE         (default /var/lib/meta-leads/healthcheck_state.json)

set -euo pipefail

HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8811/meta-leads/health}"
STATE_FILE="${STATE_FILE:-/var/lib/meta-leads/healthcheck_state.json}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

alert() {  # alert <mensagem>
  local msg="$1"
  echo "[$TS] ALERTA: $msg"
  [[ -z "$ALERT_WEBHOOK_URL" ]] && { echo "[$TS] (ALERT_WEBHOOK_URL não configurado — só log)"; return 0; }
  # payload genérico {text:...} — compatível com Slack incoming webhook e a maioria dos gateways
  curl -sS -m 15 -X POST -H "Content-Type: application/json" \
    -d "$(jq -nc --arg t "🚨 meta-leads receiver: $msg" '{text:$t}')" \
    "$ALERT_WEBHOOK_URL" >/dev/null 2>&1 || echo "[$TS] (falha ao postar no webhook de alerta)"
}

# 1. Serviço responde?
resp="$(curl -sS -m 10 "$HEALTH_URL" 2>/dev/null || true)"
if ! echo "$resp" | jq -e '.received_total' >/dev/null 2>&1; then
  alert "health não respondeu JSON (serviço down?) em $HEALTH_URL"
  exit 1
fi

# 2. Contadores atuais
cur_err="$(echo "$resp" | jq -r '.errors // 0')"
cur_nocfg="$(echo "$resp" | jq -r '.no_config // 0')"
cur_malf="$(echo "$resp" | jq -r '.malformed // 0')"
last_status="$(echo "$resp" | jq -r '.last_status // "null"')"

# 3. Compara com a última execução (delta > 0 = novas falhas desde o último check)
prev_err=0; prev_nocfg=0; prev_malf=0
if [[ -f "$STATE_FILE" ]]; then
  prev_err="$(jq -r '.errors // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  prev_nocfg="$(jq -r '.no_config // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  prev_malf="$(jq -r '.malformed // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
fi

(( cur_err   > prev_err   )) && alert "$(( cur_err - prev_err )) nova(s) falha(s) de entrega (errors=$cur_err) — leads podem estar expirando na janela de retry. Ver events.jsonl."
(( cur_nocfg > prev_nocfg )) && alert "$(( cur_nocfg - prev_nocfg )) lead(s) de página SEM config (no_config=$cur_nocfg) — página não mapeada no config.json."
(( cur_malf  > prev_malf  )) && alert "$(( cur_malf - prev_malf )) payload(s) malformado(s) (malformed=$cur_malf) — anomalia; investigar."
[[ "$last_status" == error:* ]] && alert "último evento falhou (last_status=$last_status)."

# 4. Persiste o estado desta execução
mkdir -p "$(dirname "$STATE_FILE")"
echo "$resp" | jq -c '{errors, no_config, malformed, checked_at: "'"$TS"'"}' > "$STATE_FILE"
echo "[$TS] ok — errors=$cur_err no_config=$cur_nocfg malformed=$cur_malf last_status=$last_status"
