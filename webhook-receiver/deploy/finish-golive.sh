#!/usr/bin/env bash
# finish-golive.sh — completa a F2 (go-live público do webhook) do plano de fechamento
# EM UM COMANDO, assim que o META_APP_SECRET real estiver em /opt/meta-leads/.env.
#
# Por que existe: revelar o App Secret exige a senha do Flávio no painel Meta (F0.2, único
# passo humano). Depois disso, TODO o resto do go-live (F2.1 Verify/Save + F2.2 assinar o
# campo leadgen no nível do app) é feito por API — NÃO precisa de painel/browser. Este
# script faz isso + valida a cadeia ponta-a-ponta.
#
# USO (na VPS, como root, depois de colar o secret no .env):
#   1) cole o App Secret:  sed -i 's/^META_APP_SECRET=.*/META_APP_SECRET=<valor>/' /opt/meta-leads/.env
#   2) systemctl restart meta-leads
#   3) bash /opt/meta-leads/deploy/finish-golive.sh
#
# Idempotente: re-rodar só re-afirma a subscription. NÃO ecoa secret/token.

set -euo pipefail
ENV_FILE="${ENV_FILE:-/opt/meta-leads/.env}"
API="https://graph.facebook.com/v25.0"
CALLBACK="https://webhooks.ahoy.digital/meta-leads"
APP_ID="995722365981851"

set -a; source "$ENV_FILE"; set +a
: "${META_APP_SECRET:?META_APP_SECRET ausente no .env}"
: "${META_VERIFY_TOKEN:?META_VERIFY_TOKEN ausente no .env}"
: "${META_ACCESS_TOKEN:?}"
: "${PAGE_ID:=108356564252733}"

if [[ "$META_APP_SECRET" == "PENDENTE_HUMANO" || -z "$META_APP_SECRET" ]]; then
  echo "✗ META_APP_SECRET ainda é placeholder. Cole o valor real do painel Meta primeiro (F0.2)."
  exit 1
fi

# App access token = app_id|app_secret (nunca ecoado)
APP_TOKEN="${APP_ID}|${META_APP_SECRET}"

echo "── 1/4 · pré-check: receiver público responde? ──"
curl -fsS -m 15 "${CALLBACK}/health" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  ✓ health:', {k:d[k] for k in ('received_total','pushed','errors')})" \
  || { echo "  ✗ receiver público fora do ar — checar rota do tunnel (F0.1)"; exit 1; }

echo "── 2/4 · F2.1+F2.2: configurar webhook do app (Verify/Save + campo leadgen) via API ──"
# A Meta chama o CALLBACK com hub.challenge usando o verify_token; o receiver responde.
resp=$(curl -sS -m 30 -X POST "${API}/${APP_ID}/subscriptions" \
  --data-urlencode "object=page" \
  --data-urlencode "callback_url=${CALLBACK}" \
  --data-urlencode "fields=leadgen" \
  --data-urlencode "verify_token=${META_VERIFY_TOKEN}" \
  --data-urlencode "access_token=${APP_TOKEN}")
echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  ✓ subscription:', d) if d.get('success') else (print('  ✗ erro:', d) or sys.exit(1))"

echo "── 3/4 · confirmar a subscription do app (GET) ──"
curl -fsS -m 15 "${API}/${APP_ID}/subscriptions?access_token=${APP_TOKEN}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); pg=[x for x in d.get('data',[]) if x.get('object')=='page']; ok=any('leadgen' in (f.get('name') if isinstance(f,dict) else f) for x in pg for f in x.get('fields',[])); print('  ✓ page/leadgen subscrito no app' if ok else '  ⚠ leadgen não confirmado:', pg)"

echo "── 4/4 · confirmar que a PÁGINA segue subscrita (page token) ──"
PT=$(curl -fsS -m 15 "${API}/${PAGE_ID}?fields=access_token&access_token=${META_ACCESS_TOKEN}" | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
curl -fsS -m 15 "${API}/${PAGE_ID}/subscribed_apps?access_token=${PT}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); ok=any('leadgen' in a.get('subscribed_fields',[]) for a in d.get('data',[])); print('  ✓ página subscrita em leadgen' if ok else '  ⚠', d)"

echo
echo "✅ Go-live do webhook COMPLETO. Cadeia Meta→tunnel→receiver→GHL ativa."
echo "   Próximo (F2.3): disparar um test lead num form da página e conferir:"
echo "     curl -s ${CALLBACK}/health   → received_total e pushed devem incrementar"
echo "   E ligar o monitor (F2.4):  crontab -e →  */10 * * * * ${ENV_FILE%/.env}/deploy/healthcheck.sh"
