#!/usr/bin/env bash
# visual-preview.sh — gera ASCII tree ou HTML com mock do Meta
#
# FU-1/FU-4 fix: payloads passam por stdin (nunca heredoc com interpolação).
# Scripts Python standalone em lib/_py/preview_ascii.py e preview_html.py.
# Compatível com user-controlled JSON (lead form labels, ad text).

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
