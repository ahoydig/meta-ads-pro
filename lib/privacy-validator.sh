#!/usr/bin/env bash
# privacy-validator.sh — wrapper de validação de privacy policy URL com cache 24h.
#
# Uso:
#   source lib/privacy-validator.sh
#   validate_privacy_url "https://site.com/privacy" || { echo "URL inválida"; exit 1; }
#
# Delegates pra lib/_py/privacy_check.py (3 camadas bilíngue).
# Cache em ~/.claude/meta-ads-pro/cache/privacy/{sha256(url)} com TTL 24h.
#
# FU-1 compliant: URL passa via argv do Python (não heredoc), sem risco de injection.
# Fix do bug #7 do caso Filipe.

set -euo pipefail

_pv_cache_dir() {
  echo "${HOME}/.claude/meta-ads-pro/cache/privacy"
}

_pv_ensure_cache_dir() {
  local dir
  dir=$(_pv_cache_dir)
  [[ -d "$dir" ]] || mkdir -p "$dir"
}

_pv_url_hash() {
  # sha256 do URL normalizado (trim whitespace) — bash 3.2 portable
  local url="$1"
  printf '%s' "$url" | shasum -a 256 | awk '{print $1}'
}

_pv_now() {
  date +%s
}

validate_privacy_url() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    echo "validate_privacy_url: URL vazia" >&2
    return 2
  fi

  _pv_ensure_cache_dir
  local cache_dir url_hash cache_file now cached_at cached_result age
  cache_dir=$(_pv_cache_dir)
  url_hash=$(_pv_url_hash "$url")
  cache_file="$cache_dir/$url_hash"
  now=$(_pv_now)

  # Cache hit?
  if [[ -f "$cache_file" ]]; then
    cached_at=$(jq -r '.validated_at // 0' "$cache_file" 2>/dev/null || echo 0)
    cached_result=$(jq -r '.result // ""' "$cache_file" 2>/dev/null || echo "")
    age=$(( now - cached_at ))
    if [[ "$cached_at" != "0" ]] && (( age < 86400 )); then
      if [[ "$cached_result" == "OK" ]]; then
        echo "OK"
        return 0
      else
        # repete o REJECT cacheado no stderr
        echo "$cached_result" >&2
        return 1
      fi
    fi
  fi

  # Cache miss ou stale: roda Python validator
  local py_script
  py_script="$(dirname "${BASH_SOURCE[0]}")/_py/privacy_check.py"
  if [[ ! -f "$py_script" ]]; then
    echo "validate_privacy_url: privacy_check.py não encontrado em $py_script" >&2
    return 2
  fi

  local output rc
  # URL passa via argv (não via stdin/heredoc) — FU-1 compliant.
  # Captura stdout+stderr num var único pra persistir no cache.
  output=$(python3 "$py_script" "$url" 2>&1) || rc=$?
  rc=${rc:-0}

  if (( rc == 0 )); then
    # persiste OK no cache (jq -n pra JSON seguro)
    jq -n \
      --arg url "$url" \
      --arg result "OK" \
      --argjson validated_at "$now" \
      '{url:$url, result:$result, validated_at:$validated_at}' \
      > "$cache_file"
    echo "OK"
    return 0
  fi

  # Rejected: persiste REJECT + motivo. Mostra REJECT no stderr do caller.
  local reject_msg
  reject_msg=$(printf '%s' "$output" | head -n1)
  [[ -z "$reject_msg" ]] && reject_msg="REJECT: privacy_check.py exited $rc"

  jq -n \
    --arg url "$url" \
    --arg result "$reject_msg" \
    --argjson validated_at "$now" \
    '{url:$url, result:$result, validated_at:$validated_at}' \
    > "$cache_file"

  echo "$reject_msg" >&2
  return 1
}

# Invalidate cache pra 1 URL (útil em tests ou após user corrigir a página)
invalidate_privacy_cache() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    echo "invalidate_privacy_cache: URL vazia" >&2
    return 2
  fi
  local cache_dir url_hash cache_file
  cache_dir=$(_pv_cache_dir)
  url_hash=$(_pv_url_hash "$url")
  cache_file="$cache_dir/$url_hash"
  [[ -f "$cache_file" ]] && rm -f "$cache_file"
  return 0
}

# Se invocado direto (não via source), valida o argumento e sai
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  validate_privacy_url "$@"
fi
