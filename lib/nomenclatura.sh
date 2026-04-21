#!/usr/bin/env bash
# nomenclatura.sh — gera nomes padronizados pra campanha/adset/ad

set -euo pipefail

apply_template() {
  local template="$1"; shift
  local result="$template"
  for kv in "$@"; do
    local k="${kv%%=*}"
    local v="${kv#*=}"
    result="${result//\{$k\}/$v}"
  done
  echo "$result"
}

# gen_name <level> <style> k1=v1 k2=v2 ...
# level: campaign|adset|ad
# style: ahoy-style | enxuto | custom
gen_name() {
  local level="$1" style="$2"; shift 2
  local today
  today=$(date +%Y%m%d)

  case "$style" in
    ahoy-style)
      case "$level" in
        campaign)
          # {prefix}_{YYYYMMDD}_{produto}_{objetivo}_{destino}_{opt}_{publico}
          local prefix="${NOMENCLATURA_PREFIX:-ahoy}"
          apply_template "${prefix}_${today}_{produto}_{objetivo}_{destino}_{opt}_{publico}" "$@" \
            | sed 's/_[{][a-zA-Z][a-zA-Z-]*[}]//g'
          ;;
        adset)
          apply_template "{tipopublico}_{nomeaudiencia}_auto_{idade}_{genero}_{regiao}" "$@" \
            | sed 's/_[{][a-zA-Z][a-zA-Z-]*[}]//g'
          ;;
        ad)
          apply_template "{formato}_{nome-criativo}_{avatar}_{tipo}_{cta}_v{N}" "$@" \
            | sed 's/_[{][a-zA-Z][a-zA-Z-]*[}]//g'
          ;;
        *)
          echo "gen_name: level inválido '$level'" >&2
          return 1
          ;;
      esac
      ;;
    enxuto)
      case "$level" in
        campaign) apply_template "${today}-{produto}-{objetivo}" "$@" ;;
        adset) apply_template "{publico}-{regiao}" "$@" ;;
        ad) apply_template "{formato}-{nome-criativo}" "$@" ;;
        *)
          echo "gen_name: level inválido '$level'" >&2
          return 1
          ;;
      esac
      ;;
    custom)
      # lê template do env (setada pelo setup)
      local tmpl_var
      tmpl_var="NOMENCLATURA_TEMPLATE_$(echo "$level" | tr '[:lower:]' '[:upper:]')"
      local tmpl="${!tmpl_var:-}"
      [[ -n "$tmpl" ]] || { echo "gen_name: custom style mas template $tmpl_var vazio" >&2; return 1; }
      apply_template "$tmpl" "$@"
      ;;
    *)
      echo "gen_name: style inválido '$style'" >&2
      return 1
      ;;
  esac
}

# Detecta padrão a partir de amostra — delega pra script standalone
# Ex: detect_pattern "[FORMULARIO][PACIENTE-MODELO][AUTO]"
#  → "[{TOKEN1}][{TOKEN2}][{TOKEN3}]"
detect_pattern() {
  local sample="$1"
  python3 "$(dirname "${BASH_SOURCE[0]}")/_py/detect_pattern.py" "$sample"
}
