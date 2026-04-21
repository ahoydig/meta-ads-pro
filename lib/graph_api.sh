#!/usr/bin/env bash
# graph_api.sh — wrapper curl pra Graph API v25.0
# Uso: graph_api GET "me?fields=name,id"
#      graph_api POST "act_{id}/campaigns" '{"name":"...","objective":"..."}'
#      graph_api DELETE "{object_id}"

set -euo pipefail

API_VERSION="${META_API_VERSION:-v25.0}"
MAX_RETRIES=2
RETRY_DELAY=60  # sec pra 613/80004

graph_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url="https://graph.facebook.com/${API_VERSION}/${path}"
  local token="${META_ACCESS_TOKEN:?META_ACCESS_TOKEN não setado}"
  local attempt=0
  local response
  local http_code

  # Guard: body vazio vira objeto vazio pra jq não quebrar
  [[ -z "$body" ]] && body='{}'

  while (( attempt <= MAX_RETRIES )); do
    if [[ "$method" == "GET" ]]; then
      # separador correto entre query existente e access_token
      if [[ "$url" == *"?"* ]]; then
        response=$(curl -sS -w "\n%{http_code}" "${url}&access_token=${token}")
      else
        response=$(curl -sS -w "\n%{http_code}" "${url}?access_token=${token}")
      fi
    elif [[ "$method" == "POST" ]]; then
      local body_with_token
      body_with_token=$(echo "$body" | jq --arg t "$token" '. + {access_token:$t}')
      response=$(curl -sS -w "\n%{http_code}" -X POST -H "Content-Type: application/json" \
        -d "$body_with_token" \
        "$url")
    elif [[ "$method" == "DELETE" ]]; then
      response=$(curl -sS -w "\n%{http_code}" -X DELETE "${url}?access_token=${token}")
    else
      echo "graph_api: método inválido $method" >&2
      return 1
    fi

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    # 200/201 success
    if [[ "$http_code" =~ ^2 ]]; then
      echo "$response"
      return 0
    fi

    # extrai error code
    local err_code err_subcode
    err_code=$(echo "$response" | jq -r '.error.code // empty')
    err_subcode=$(echo "$response" | jq -r '.error.error_subcode // empty')

    # transiente: retry
    if [[ "$http_code" =~ ^5 ]] || [[ "$err_code" == "613" ]] || [[ "$err_code" == "80004" ]]; then
      (( attempt++ ))
      if (( attempt <= MAX_RETRIES )); then
        local delay=$(( RETRY_DELAY * attempt ))
        echo "⚠ graph_api: erro transiente (${http_code}/${err_code}), retry em ${delay}s (${attempt}/${MAX_RETRIES})" >&2
        sleep "$delay"
        continue
      fi
    fi

    # erro permanente: envia pra error_resolver (se existir)
    local resolver_sh
    resolver_sh="$(dirname "${BASH_SOURCE[0]}")/error-resolver.sh"
    if [[ -f "$resolver_sh" ]] && [[ "${GRAPH_API_SKIP_RESOLVER:-0}" != "1" ]]; then
      # shellcheck source=/dev/null
      source "$resolver_sh"
      resolve_error "$err_code" "$err_subcode" "$response" "$method" "$path" "$body" && return 0
    fi

    # falhou: ecoa response e retorna erro
    echo "$response" >&2
    return 1
  done

  echo "graph_api: max retries excedido" >&2
  return 1
}

# If invoked directly (not sourced), pass args through
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  graph_api "$@"
fi
