#!/usr/bin/env bash
# visual-preview.sh — gera ASCII tree ou HTML com mock do Meta
#
# FU-1/FU-4 fix: payloads passam por stdin (nunca heredoc com interpolação).
# Scripts Python standalone em lib/_py/preview_ascii.py e preview_html.py.
# Compatível com user-controlled JSON (lead form labels, ad text).
#
# Task 14: preview_meta_oficial() usa o endpoint OFICIAL `generatepreviews`
# (creative spec) / `{creative_id}/previews` (creative já criado) da Graph
# API — iframe real da Meta, não mock local. Ver docs/spikes/ se existir
# spike específico deste endpoint.

set -euo pipefail

_PY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/_py" && pwd)"

# Build envelope JSON { level, payload, extras } via jq a partir de argv.
# Args: level, payload_json[, extras_json]
_build_envelope() {
  local level="$1" payload="$2" extras="${3:-}"
  [[ -n "$extras" ]] || extras='{}'
  # Validação mínima: payload e extras precisam ser JSON válidos.
  echo "$payload" | jq -e . >/dev/null 2>&1 \
    || { echo "visual-preview: payload não é JSON válido" >&2; return 1; }
  echo "$extras" | jq -e . >/dev/null 2>&1 \
    || { echo "visual-preview: extras não é JSON válido" >&2; return 1; }
  jq -cn \
    --arg lvl "$level" \
    --argjson payload "$payload" \
    --argjson extras "$extras" \
    '{level:$lvl, payload:$payload, extras:$extras}'
}

# preview_ascii <level> <payload_json> [extras_json]
preview_ascii() {
  local level="$1" payload="$2" extras="${3:-}"
  [[ -n "$extras" ]] || extras='{}'
  local envelope
  envelope=$(_build_envelope "$level" "$payload" "$extras") || return 1
  printf '%s' "$envelope" | python3 "${_PY_DIR}/preview_ascii.py"
}

# preview_html <level> <payload_json> [extras_json] → echoa path do arquivo HTML
preview_html() {
  local level="$1" payload="$2" extras="${3:-}"
  [[ -n "$extras" ]] || extras='{}'
  local envelope out_file
  envelope=$(_build_envelope "$level" "$payload" "$extras") || return 1
  out_file=$(mktemp -t meta-ads-preview.XXXXXX.html)
  printf '%s' "$envelope" | python3 "${_PY_DIR}/preview_html.py" > "$out_file"
  echo "$out_file"
}

# ─── backward-compat shims (preview_ascii_campaign, preview_html_campaign) ───
# Assinatura antiga: preview_ascii_campaign <camp_json> <adset_json> <ads_json>
preview_ascii_campaign() {
  local camp_json="$1" adset_json="$2" ads_json="$3"
  local extras
  extras=$(jq -cn \
    --argjson adset "$adset_json" \
    --argjson ads "$ads_json" \
    '{adset:$adset, ads:$ads}')
  preview_ascii "campaign" "$camp_json" "$extras"
}

preview_html_campaign() {
  local camp_json="$1"
  # shellcheck disable=SC2016
  local adset_json='{}'
  local ads_json='[]'
  if [[ "${2:-}" != "" ]]; then adset_json="$2"; fi
  if [[ "${3:-}" != "" ]]; then ads_json="$3"; fi
  local extras
  extras=$(jq -cn \
    --argjson adset "$adset_json" \
    --argjson ads "$ads_json" \
    '{adset:$adset, ads:$ads}')
  preview_html "campaign" "$camp_json" "$extras"
}

# ─── preview_meta_oficial: iframe OFICIAL da Meta (generatepreviews) ───────
# Task 14: diferente de preview_ascii/preview_html (mock local, offline,
# instantâneo), este preview é FIEL — vem direto da Graph API, mas custa uma
# chamada de rede (GET, barato) por formato.
#
# uso: preview_meta_oficial <creative_spec_json|creative_id> <ad_format> [ad_format...]
#
#   1º arg:     JSON de creative spec (ex.: {"object_story_spec":{...}}) OU
#               um creative_id numérico de um adcreative já criado.
#               Detecção automática: só dígitos → creative_id (usa
#               {creative_id}/previews); JSON *objeto* → spec (usa
#               {AD_ACCOUNT_ID}/generatepreviews). Qualquer outra coisa é erro.
#   ad_format:  1 ou mais de MOBILE_FEED_STANDARD, INSTAGRAM_STANDARD,
#               INSTAGRAM_STORY, INSTAGRAM_REELS (default: MOBILE_FEED_STANDARD
#               se nenhum for passado).
#
# Requer AD_ACCOUNT_ID no ambiente quando o 1º arg é um creative spec (não é
# necessário no caminho por creative_id).
#
# Gera HTML único (um <h2> por formato) em
# ~/.claude/meta-ads-pro/previews/preview_<timestamp>.html, abre no browser
# (open/xdg-open/cmd.exe conforme OS) e ecoa o path do arquivo.
preview_meta_oficial() {
  local ref="${1:?preview_meta_oficial: creative_spec_json ou creative_id obrigatório}"
  shift || true
  local ad_formats=("$@")
  [[ ${#ad_formats[@]} -gt 0 ]] || ad_formats=("MOBILE_FEED_STANDARD")

  # source graph_api se ainda não estiver disponível (permite chamada standalone)
  if ! command -v graph_api >/dev/null 2>&1; then
    # shellcheck source=./graph_api.sh disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/graph_api.sh"
  fi

  # Detecção: creative_id é sempre um ID numérico puro da Graph API. Um creative
  # spec é um JSON *objeto* (ex.: {"object_story_spec":{...}}). Checar só "é JSON
  # válido" não basta — um ID numérico puro (ex.: 120217729321860196) também é
  # JSON válido (número escalar) e seria roteado errado pro endpoint errado.
  local is_spec=0
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    is_spec=0
  elif echo "$ref" | jq -e 'type == "object"' >/dev/null 2>&1; then
    is_spec=1
  else
    echo "preview_meta_oficial: 1º argumento não é um creative_id numérico nem um JSON de creative spec (objeto): $ref" >&2
    return 1
  fi

  if [[ "$is_spec" == "1" ]] && [[ -z "${AD_ACCOUNT_ID:-}" ]]; then
    echo "preview_meta_oficial: AD_ACCOUNT_ID não setado no ambiente (obrigatório pra creative spec via generatepreviews)" >&2
    return 1
  fi

  local out_dir="${HOME}/.claude/meta-ads-pro/previews"
  mkdir -p "$out_dir"
  local out_file
  out_file="${out_dir}/preview_$(date +%s).html"

  {
    printf '%s\n' '<!DOCTYPE html><html><head><meta charset="utf-8">'
    printf '%s\n' '<title>Preview oficial Meta</title>'
    printf '%s\n' '<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  background:#f0f2f5;margin:0;padding:2em 1em;color:#1c1e21}
.container{max-width:640px;margin:0 auto}
h1{font-size:1.2em}
h2{margin-top:2em;font-size:1em;color:#65676b;
  border-bottom:1px solid #dddfe2;padding-bottom:.3em}
iframe{border:none;width:100%;min-height:600px;background:#fff}
p.warn{color:#c0392b}
</style>'
    printf '%s\n' '</head><body><div class="container">'
    printf '<h1>Preview oficial Meta (generatepreviews)</h1>\n'

    local fmt body first=1
    for fmt in "${ad_formats[@]}"; do
      # sleep entre chamadas — GET é barato, mas outro track pode usar a mesma conta
      if [[ "$first" != "1" ]]; then
        sleep "${PREVIEW_META_OFICIAL_SLEEP:-5}"
      fi
      first=0

      printf '<h2>%s</h2>\n' "$fmt"
      if [[ "$is_spec" == "1" ]]; then
        local encoded
        encoded=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$ref")
        body=$(graph_api GET "${AD_ACCOUNT_ID}/generatepreviews?creative=${encoded}&ad_format=${fmt}" 2>/dev/null | jq -r '.data[0].body // empty')
      else
        body=$(graph_api GET "${ref}/previews?ad_format=${fmt}" 2>/dev/null | jq -r '.data[0].body // empty')
      fi

      if [[ -n "$body" ]]; then
        printf '%s\n' "$body"
      else
        printf '<p class="warn">⚠ sem preview disponível pra %s (confira formato/creative)</p>\n' "$fmt"
      fi
    done

    printf '%s\n' '</div></body></html>'
  } > "$out_file"

  open "$out_file" 2>/dev/null \
    || xdg-open "$out_file" 2>/dev/null \
    || cmd.exe /c start "$out_file" 2>/dev/null \
    || echo "preview oficial: abra manualmente $out_file" >&2

  echo "$out_file"
}

# ─── Confirmação obrigatória antes de POST ──────────────────────────────────
# FU-4: preview_fn parameter reintroduzido pra extensibilidade.
#
# uso: preview_and_confirm <level> <payload_json> [preview_fn] [extras_json]
#
#   level:       campaign|adset|ad|leadform|generic
#   payload:     JSON dict do objeto
#   preview_fn:  (opcional) nome de função bash que, recebendo payload via arg $1
#                e extras via arg $2, imprime o preview HTML e ecoa o path.
#                Default: preview_html (função genérica do arquivo).
#   extras:      JSON dict com dependências (adset+ads pra level=campaign)
#
# Retorna 0 se user confirma, 1 se não.
preview_and_confirm() {
  local level="$1"
  local payload="$2"
  local preview_fn="${3:-preview_html}"
  local extras="${4:-}"
  [[ -n "$extras" ]] || extras='{}'

  # ASCII preview sempre roda primeiro (inline)
  preview_ascii "$level" "$payload" "$extras" || return 1

  echo ""
  local ans
  read -rp "Confirma criação? [s/N/p=preview HTML no browser] " ans
  case "$ans" in
    s|S) return 0 ;;
    p|P)
      local html
      if [[ "$preview_fn" == "preview_html" ]]; then
        html=$(preview_html "$level" "$payload" "$extras") || return 1
      else
        # Função customizada — recebe (payload, extras) e ecoa path.
        html=$("$preview_fn" "$payload" "$extras") || return 1
      fi
      # macOS: open; Linux: xdg-open; WSL: cmd.exe /c start
      open "$html" 2>/dev/null \
        || xdg-open "$html" 2>/dev/null \
        || cmd.exe /c start "$html" 2>/dev/null \
        || echo "preview visual: abra manualmente $html" >&2
      local ans2
      read -rp "Confirma após ver o preview? [s/N] " ans2
      [[ "$ans2" == "s" || "$ans2" == "S" ]]
      ;;
    *) return 1 ;;
  esac
}
