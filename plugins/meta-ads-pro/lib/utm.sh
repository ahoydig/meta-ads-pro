#!/usr/bin/env bash
# utm.sh — UTM Builder pra Meta Ads
# Padrão da skill nomenclatura-utm (~/.claude/skills/nomenclatura-utm/SKILL.md)
#
# Modo dinâmico (ads): macros que a Meta substitui no leilão
#   utm_source={{site_source_name}}&utm_medium=trafego-pago
#   &utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}
#
# Modo estático (lead forms, follow-up URLs): valores fixos
#   utm_source=meta&utm_medium=trafego-pago&utm_campaign={form_name|slug}

set -euo pipefail

# strip_existing_utm <url>
# Remove parâmetros utm_* da URL pra evitar duplicação ao re-aplicar.
strip_existing_utm() {
  local url="$1"
  local base query
  if [[ "$url" == *\?* ]]; then
    base="${url%%\?*}"
    query="${url#*\?}"
    local cleaned=""
    local IFS='&'
    for kv in $query; do
      [[ "$kv" == utm_*=* ]] && continue
      cleaned="${cleaned:+${cleaned}&}${kv}"
    done
    if [[ -n "$cleaned" ]]; then
      echo "${base}?${cleaned}"
    else
      echo "$base"
    fi
  else
    echo "$url"
  fi
}

# build_utm_url_dynamic <base_url>
# Aplica macros dinâmicas Meta. Resultado: URL com {{macros}} que Meta substitui.
# Use SEMPRE pra link_url de ad creative (object_story_spec, asset_feed_spec).
build_utm_url_dynamic() {
  local base_url="$1"
  base_url=$(strip_existing_utm "$base_url")
  local sep="?"
  [[ "$base_url" == *\?* ]] && sep="&"
  printf '%s%sutm_source={{site_source_name}}&utm_medium=trafego-pago&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}\n' \
    "$base_url" "$sep"
}

# build_utm_url_static <base_url> <campaign_slug> [source=meta] [medium=trafego-pago]
# Aplica UTM estático (sem macros). Use pra lead form follow-up, thank you website_url,
# qualquer link onde Meta não substitui {{macro}}.
build_utm_url_static() {
  local base_url="$1"
  local campaign_slug="$2"
  local source="${3:-meta}"
  local medium="${4:-trafego-pago}"
  base_url=$(strip_existing_utm "$base_url")
  local sep="?"
  [[ "$base_url" == *\?* ]] && sep="&"
  printf '%s%sutm_source=%s&utm_medium=%s&utm_campaign=%s\n' \
    "$base_url" "$sep" "$source" "$medium" "$campaign_slug"
}

# slugify <text>
# Lowercase, sem acentos, espaços viram '-'. Usado pra montar utm_campaign estático.
# Usa Python (unicodedata.normalize NFD) pra ser cross-platform — BSD iconv quebra com acentos.
slugify() {
  python3 -c '
import sys, unicodedata, re
s = sys.argv[1]
s = unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode("ascii")
s = s.lower()
s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
print(s)
' "$1"
}

# is_external_url <url>
# Retorna 0 se é URL pública (http/https), 1 caso contrário.
# Filtra pra não aplicar UTM em deeplinks fb-messenger://, wa.me/, tel:, mailto:.
is_external_url() {
  [[ "$1" =~ ^https?:// ]]
}

# build_tracking_parameters <form_name> [extra_json]
# JSON de tracking pro campo tracking_parameters do lead form (volta grudado
# em cada lead). Formato exato aceito pela API: ver docs/spikes/2026-07-leadform-avancado.md.
build_tracking_parameters() {
  local form_name="$1"
  local extra="${2:-}"
  [[ -z "$extra" ]] && extra='{}'
  local slug today
  slug=$(slugify "$form_name")
  today=$(date +%Y%m%d)
  # Em colisão de chave, o extra vence (intencional) — jq `+` entre objetos
  # mantém o valor do lado direito quando a chave se repete.
  jq -nc --arg c "${today}_${slug}" --argjson extra "$extra" \
    '{utm_source:"meta-leadform", utm_medium:"trafego-pago", utm_campaign:$c} + $extra'
}
