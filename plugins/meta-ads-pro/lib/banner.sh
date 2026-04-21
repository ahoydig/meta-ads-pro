#!/usr/bin/env bash
# banner.sh — render banner com degrade em 3 níveis (sem cor)

set -euo pipefail

render_banner() {
  local banner_file
  banner_file="$(dirname "${BASH_SOURCE[0]}")/../assets/banner.txt"

  local width
  width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}

  local unicode_ok="yes"
  if [[ -z "${LC_ALL:-}" || "${LC_ALL:-}" == "C" || "${LC_ALL:-}" == "POSIX" ]]; then
    unicode_ok="no"
  fi

  if (( width < 72 )) || [[ "$unicode_ok" == "no" ]]; then
    # Fallback ASCII puro
    echo "META ADS PRO"
    echo "by @flavioahoy"
  else
    # Full banner monocromático
    cat "$banner_file"
  fi
}

# Se invocado diretamente (não sourced), renderiza
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  render_banner
fi
