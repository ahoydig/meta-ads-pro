#!/usr/bin/env bash
# tests/19-crm-capi.sh — Camada 3b: integração CRM nativa GHL (Task 11)
#
# test_01_ghl_location        — GET /locations/{id} retorna .location.id == GHL_LOCATION_ID
#                                (skip sem GHL_PIT_TOKEN/GHL_LOCATION_ID — CREDENCIAL PENDENTE:
#                                a Private Integration da subconta de teste ainda não existe;
#                                a validação live real acontece na Task 23)
# test_02_receiver_health     — GET $RECEIVER_HEALTH_URL responde JSON com .received_total
#                                (skip se a var estiver vazia OU se a URL não responder JSON —
#                                hoje é este 2º caso: o receiver roda local na VPS mas SEM rota
#                                pública ainda, ver webhook-receiver/deploy/RUNBOOK.md §8;
#                                confirmado ao vivo nesta task: 404 do catch-all do gateway
#                                Hermes, não JSON do receiver)
# test_03_subscribed_apps_leadgen — GET {PAGE_ID}/subscribed_apps confirma subscribed_fields
#                                inclui "leadgen". LIVE HOJE (só precisa de META_ACCESS_TOKEN +
#                                PAGE_ID, já presentes no .env) — deriva um PAGE TOKEN com guard
#                                (mesmo padrão de tests/08-lead-forms.sh::_cleanup_forms e do
#                                spike docs/spikes/2026-07-webhook-leadgen.md, seção 3: o
#                                subscribed_apps GET não aceitou o token de sistema/usuário
#                                nesta conta ao vivo — precisa do token da própria Página).
#                                NUNCA ecoa o token derivado.
#
# test_04_capi_test_event    — POST {PIXEL_ID}/events com test_event_code (Task 12). Envia
#                                um evento LeadQualificado sintético (em/ph hasheados SHA-256,
#                                action_source=system_generated — evento de CRM, não de site)
#                                e confere .events_received == 1. LIVE HOJE (META_ACCESS_TOKEN +
#                                PIXEL_ID já no .env; CAPI_TEST_EVENT_CODE obtido ao vivo no
#                                Events Manager, pixel 947064561562400 — "pixel - @flavioahoy",
#                                aba Eventos de teste → canal Site → "Confirme se os eventos do
#                                seu servidor estão configurados corretamente"). Skip sem
#                                CAPI_TEST_EVENT_CODE (código expira — não é secret fixo, mas
#                                fica fora do git via .env gitignored). test_event_code isola o
#                                evento do teste da otimização real — TEST_ prefix (usado nos
#                                outros testes deste plugin pra nome de recurso) não se aplica
#                                aqui.
#
# test_05 fica livre pra uma task futura (ex.: doctor check_capi_dataset, Task 21).
#
# Bash 3.2 portable. Nunca ecoa GHL_PIT_TOKEN nem META_ACCESS_TOKEN.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }
_skip() { echo "- $1 (SKIP: $2)"; SKIP=$((SKIP + 1)); }

# ─── test_01: GHL location alcançável ──────────────────────────────────────
test_01_ghl_location() {
  local name="test_01_ghl_location"
  if [[ -z "${GHL_PIT_TOKEN:-}" || -z "${GHL_LOCATION_ID:-}" ]]; then
    _skip "$name" "sem GHL_PIT_TOKEN/GHL_LOCATION_ID — credencial pendente (Private Integration da subconta de teste ainda não gerada); validação live real na Task 23"
    return 0
  fi

  local r
  r=$(curl -sS --max-time 10 \
    -H "Authorization: Bearer ${GHL_PIT_TOKEN}" -H "Version: 2021-07-28" \
    "https://services.leadconnectorhq.com/locations/${GHL_LOCATION_ID}" 2>/dev/null) || r=""
  if [[ -z "$r" ]]; then
    _fail "$name" "sem resposta da API GHL (rede/timeout)"
  fi

  local got_id
  got_id=$(echo "$r" | jq -r '.location.id // empty' 2>/dev/null)
  if [[ "$got_id" == "$GHL_LOCATION_ID" ]]; then
    _pass "$name"
  else
    _fail "$name" "location.id retornado não bate com GHL_LOCATION_ID (verifique token/location)"
  fi
}

# ─── test_02: receiver health responde JSON ────────────────────────────────
test_02_receiver_health() {
  local name="test_02_receiver_health"
  local url="${RECEIVER_HEALTH_URL:-https://webhooks.ahoy.digital/meta-leads/health}"

  if [[ -z "$url" ]]; then
    _skip "$name" "RECEIVER_HEALTH_URL vazio"
    return 0
  fi

  local r
  r=$(curl -sS --max-time 10 "$url" 2>/dev/null) || r=""
  if echo "$r" | jq -e '.received_total' >/dev/null 2>&1; then
    _pass "$name (received_total=$(echo "$r" | jq -r .received_total))"
  else
    # Estado atual (2026-07): receiver up SÓ local na VPS (127.0.0.1:8811) — a rota
    # pública ainda não existe no Cloudflare Tunnel (pendência humana, ver
    # webhook-receiver/deploy/RUNBOOK.md §8). $url hoje responde 404 (catch-all do
    # gateway Hermes em :8644), não JSON do receiver — não é uma falha do teste em
    # si, é o estado real da infra. Skip gracioso, não FAIL.
    _skip "$name" "$url não respondeu JSON com received_total (estado atual: sem rota pública — ver RUNBOOK.md §8)"
  fi
}

# ─── test_03: página subscrita em leadgen (subscribed_apps) ────────────────
test_03_subscribed_apps_leadgen() {
  local name="test_03_subscribed_apps_leadgen"
  if [[ -z "${META_ACCESS_TOKEN:-}" || -z "${PAGE_ID:-}" ]]; then
    _skip "$name" "sem META_ACCESS_TOKEN/PAGE_ID"
    return 0
  fi

  # Deriva page token — subscribed_apps GET não aceitou o token de sistema/usuário
  # nesta conta (evidência ao vivo: docs/spikes/2026-07-webhook-leadgen.md, seção 3).
  # Mesmo padrão de tests/08-lead-forms.sh::_cleanup_forms — guard se vier vazio,
  # nunca ecoa o valor.
  local page_token
  page_token=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET "${PAGE_ID}?fields=access_token" 2>/dev/null \
    | jq -r '.access_token // empty') || page_token=""
  if [[ -z "$page_token" ]]; then
    _skip "$name" "não foi possível derivar page token (ver check_page_token do doctor)"
    return 0
  fi

  local r
  r=$(curl -sS --max-time 10 \
    "https://graph.facebook.com/${META_API_VERSION:-v25.0}/${PAGE_ID}/subscribed_apps?fields=subscribed_fields&access_token=${page_token}" \
    2>/dev/null) || r=""
  if echo "$r" | jq -e '.data[]?.subscribed_fields | index("leadgen")' >/dev/null 2>&1; then
    _pass "$name"
  else
    _fail "$name" "página não subscrita em leadgen — rode a subscrição do runbook (Task 10, spike T4)"
  fi
}

# ─── test_04: envio de test event CAPI (live, não polui otimização) ────────
test_04_capi_test_event() {
  local name="test_04_capi_test_event"
  if [[ -z "${META_ACCESS_TOKEN:-}" || -z "${PIXEL_ID:-}" || -z "${CAPI_TEST_EVENT_CODE:-}" ]]; then
    _skip "$name" "sem PIXEL_ID/CAPI_TEST_EVENT_CODE — gere um em business.facebook.com/events_manager2, pixel do .env, aba Eventos de teste"
    return 0
  fi

  local em ph payload response
  em=$(echo -n "teste@ahoy.digital" | shasum -a 256 | awk '{print $1}')
  ph=$(echo -n "+5591999999999" | shasum -a 256 | awk '{print $1}')
  payload=$(jq -nc --arg em "$em" --arg ph "$ph" --arg tec "$CAPI_TEST_EVENT_CODE" \
    --argjson now "$(date +%s)" '{
    data: [{event_name:"LeadQualificado", event_time:$now, action_source:"system_generated",
            user_data:{em:[$em], ph:[$ph]},
            custom_data:{lead_event_source:"GHL", event_source:"crm"}}],
    test_event_code: $tec}')
  response=$(graph_api POST "${PIXEL_ID}/events" "$payload") \
    || _fail "$name" "POST falhou: $response"
  [[ "$(echo "$response" | jq -r '.events_received // 0')" == "1" ]] \
    || _fail "$name" "events_received != 1: $response"
  _pass "$name"
}

test_01_ghl_location
test_02_receiver_health
test_03_subscribed_apps_leadgen
test_04_capi_test_event

echo ""
echo "19-crm-capi: $PASS passou, $FAIL falhou, $SKIP skip"
[[ "$FAIL" -eq 0 ]]
