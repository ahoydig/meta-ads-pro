#!/usr/bin/env bash
# error-resolver.sh — resolve erros Graph API antes de reportar

set -euo pipefail

CATALOG="$(dirname "${BASH_SOURCE[0]}")/error-catalog.yaml"
LEARNINGS_DIR="${HOME}/.claude/meta-ads-pro/learnings"
mkdir -p "$LEARNINGS_DIR"

# Retorna fix em formato fix_fn:arg1:arg2 OU 'UNKNOWN'
get_fix_for_error() {
  local code="$1"
  local subcode="${2:-}"
  python3 <<PYEOF
import yaml, sys
with open("$CATALOG") as f:
    d = yaml.safe_load(f)
errs = d.get("errors", {})
code = int("$code") if "$code".isdigit() else "$code"
subcode = "$subcode" or "*"
if code not in errs:
    print("UNKNOWN"); sys.exit(0)
entry = errs[code].get(int(subcode) if subcode != "*" and str(subcode).isdigit() else "*")
if entry is None:
    # fallback pra wildcard
    entry = errs[code].get("*")
if entry is None:
    print("UNKNOWN"); sys.exit(0)
fix_fn = entry.get("fix_fn") or entry.get("action") or "UNKNOWN"
args = entry.get("fix_args", [])
def fmt_arg(a):
    if isinstance(a, bool):
        return str(a).lower()
    return str(a)
if args:
    print(fix_fn + ":" + ":".join(fmt_arg(a) for a in args))
else:
    print(fix_fn)
PYEOF
}

# Tenta resolver erro automaticamente. Retorna 0 se resolveu, 1 se não.
resolve_error() {
  local code="$1" subcode="${2:-}" response="$3" path="$5"
  # method ($4) e body ($6) reservados pra CP2 (fix automático de body)
  # shellcheck disable=SC2034
  local _method="$4"
  # shellcheck disable=SC2034
  local _body="${6:-}"
  local fix
  fix=$(get_fix_for_error "$code" "$subcode")

  if [[ "$fix" == "UNKNOWN" ]]; then
    log_unknown_error "$code" "$subcode" "$response" "$path"
    return 1
  fi

  # parse fix_fn:args
  local fn="${fix%%:*}"
  local args_str="${fix#"$fn"}"
  args_str="${args_str#:}"

  echo "⚙ error-resolver: aplicando fix '$fn' pra erro $code/$subcode" >&2

  case "$fn" in
    add_field|add_nested)
      # aplicação do fix exige re-POST modificando body — exporta FIX pro caller
      # aplicar via apply_fix_to_body() e retentar uma vez.
      echo "FIX:$fix" >&2
      # shellcheck disable=SC2034  # RESOLVER_FIX é lida pelo graph_api.sh (caller)
      RESOLVER_FIX="$fix"
      export RESOLVER_FIX
      return 2  # código especial: caller deve aplicar e retentar
      ;;
    sleep_and_retry)
      local delay="${args_str:-60}"
      echo "⏸ sleep $delay segundos" >&2
      sleep "$delay"
      return 2  # retentar
      ;;
    prompt_rerun_setup|prompt_missing_scopes|prompt_user|prompt_user_check_account|prompt_user_file_check|prompt_user_rename|prompt_user_adjust_date|halt_with_message|list_dependent_lookalikes|prompt_missing_scope_instagram|prompt_user_with_min|prompt_user_page_token|prompt_user_connect_whatsapp|prompt_user_check_form)
      # ações que exigem user input — retorna erro pra UI handler
      echo "USER_ACTION:$fn" >&2
      return 1
      ;;
    switch_to_dark_post_flow)
      # Fix bug #3: Graph API rejeita object_story_spec quando app em dev mode.
      # Re-escreve body com object_story_id apontando pra dark post recém-criado.
      # Caller re-executa POST com o novo body via RESOLVER_NEW_BODY.
      local new_body
      new_body=$(switch_to_dark_post_flow "${_body:-}") || {
        echo "switch_to_dark_post_flow: falhou" >&2
        return 1
      }
      export RESOLVER_NEW_BODY="$new_body"
      echo "FIX:switch_to_dark_post_flow" >&2
      return 2
      ;;
    read_buc_header_and_wait|offer_sips_resize|add_placement_sibling|regenerate_media_fbid)
      # implementação em CPs posteriores
      echo "TODO_CP_FUTURE:$fn" >&2
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# Aplica fix ao body JSON e ecoa o novo body.
# fix formato: "add_field:<key>:<value>"  ou  "add_nested:<dot.path>:<value>"
# value é interpretado como JSON se bool/numérico/null, senão como string.
# Usage: new_body=$(apply_fix_to_body "$body" "$fix")
apply_fix_to_body() {
  local body="$1" fix="$2"
  [[ -z "$fix" ]] && { echo "$body"; return 1; }
  [[ -z "$body" ]] && body='{}'

  local fn rest key value
  fn="${fix%%:*}"
  rest="${fix#*:}"
  key="${rest%%:*}"
  value="${rest#*:}"

  local is_json=0
  if [[ "$value" == "true" || "$value" == "false" || "$value" == "null" ]] \
     || [[ "$value" =~ ^-?[0-9]+$ ]] \
     || [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
    is_json=1
  fi

  case "$fn" in
    add_field)
      if (( is_json )); then
        echo "$body" | jq -c --arg k "$key" --argjson v "$value" '. + {($k): $v}'
      else
        echo "$body" | jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}'
      fi
      ;;
    add_nested)
      local path_json
      path_json=$(printf '%s' "$key" | jq -Rc 'split(".")')
      if (( is_json )); then
        echo "$body" | jq -c --argjson p "$path_json" --argjson v "$value" 'setpath($p; $v)'
      else
        echo "$body" | jq -c --argjson p "$path_json" --arg v "$value" 'setpath($p; $v)'
      fi
      ;;
    *)
      echo "$body"
      return 1
      ;;
  esac
}

# ─── switch_to_dark_post_flow ─────────────────────────────────────────────────
# Fix bug #3: app em dev mode → Graph rejeita object_story_spec.
# Workaround: criar dark post (feed published=false) usando page access token,
# depois re-POST o creative com object_story_id em vez de object_story_spec.
#
# Input:  $1 = body JSON original que falhou (tem object_story_spec)
# Output: novo body JSON (object_story_id + call_to_action preservado)
#
# Requer: PAGE_ACCESS_TOKEN no env.
# Dependências: upload_dark_post (lib/upload_media.sh) quando há image_hash
# fresh; aqui refazemos com message+link (sem reusar image_hash).
switch_to_dark_post_flow() {
  local original_body="$1"
  [[ -n "$original_body" ]] || {
    echo "switch_to_dark_post_flow: body vazio" >&2
    return 1
  }

  local page_id caption link cta_json image_hash
  page_id=$(echo "$original_body"    | jq -r '.object_story_spec.page_id // empty')
  caption=$(echo "$original_body"    | jq -r '.object_story_spec.link_data.message // .object_story_spec.video_data.message // empty')
  link=$(echo "$original_body"       | jq -r '.object_story_spec.link_data.link // empty')
  cta_json=$(echo "$original_body"   | jq -c '.object_story_spec.link_data.call_to_action // .object_story_spec.video_data.call_to_action // null')
  image_hash=$(echo "$original_body" | jq -r '.object_story_spec.link_data.image_hash // empty')

  [[ -n "$page_id" ]] || {
    echo "switch_to_dark_post_flow: page_id ausente no object_story_spec" >&2
    return 1
  }

  local page_token="${PAGE_ACCESS_TOKEN:-}"
  if [[ -z "$page_token" ]]; then
    # tenta buscar via token do usuário
    local user_token="${META_ACCESS_TOKEN:-}"
    [[ -n "$user_token" ]] || {
      echo "switch_to_dark_post_flow: PAGE_ACCESS_TOKEN nem META_ACCESS_TOKEN disponíveis" >&2
      return 1
    }
    local api_ver="${META_API_VERSION:-v25.0}"
    page_token=$(curl -sS \
      "https://graph.facebook.com/${api_ver}/${page_id}?fields=access_token&access_token=${user_token}" \
      | jq -r '.access_token // empty')
    [[ -n "$page_token" ]] || {
      echo "switch_to_dark_post_flow: page token indisponível (pages_manage_posts/pages_read_engagement scope?)" >&2
      return 1
    }
  fi

  local api_ver="${META_API_VERSION:-v25.0}"

  # Cria dark post via /{page_id}/feed published=false
  local curl_args=(-sS -X POST "https://graph.facebook.com/${api_ver}/${page_id}/feed"
    -F "message=${caption}"
    -F "published=false"
    -F "access_token=${page_token}")
  [[ -n "$link" ]] && curl_args+=(-F "link=${link}")

  # Se tem image_hash, reaproveita via attached_media (foto já na biblioteca)
  # Nota: bug #5 diz "nunca reusar media_fbid entre posts" — aqui é o MESMO
  # run que falhou, então criar UM novo post e abandonar o antigo é seguro.
  if [[ -n "$image_hash" ]]; then
    curl_args+=(-F "image_hash=${image_hash}")
  fi

  local post_response post_id
  post_response=$(curl "${curl_args[@]}")
  post_id=$(echo "$post_response" | jq -r '.id // empty')
  [[ -n "$post_id" ]] || {
    echo "switch_to_dark_post_flow: falhou ao criar dark post — $post_response" >&2
    return 1
  }

  # Registra no manifest pra rollback (se manifest_add disponível)
  if command -v manifest_add >/dev/null 2>&1; then
    manifest_add "dark_post" "$post_id" 2>/dev/null || true
  fi

  # Constrói novo body: object_story_id + call_to_action preservado
  if [[ "$cta_json" == "null" || -z "$cta_json" ]]; then
    jq -n --arg pid "$post_id" '{object_story_id: $pid}'
  else
    jq -n --arg pid "$post_id" --argjson cta "$cta_json" \
      '{object_story_id: $pid, call_to_action: $cta}'
  fi
}

log_unknown_error() {
  local code="$1" subcode="$2" response="$3" path="$4"
  local file="$LEARNINGS_DIR/unknown_errors.jsonl"
  local py_script
  py_script="$(dirname "${BASH_SOURCE[0]}")/_py/log_unknown_error.py"
  printf '%s' "$response" | python3 "$py_script" \
    --code "$code" --subcode "$subcode" --path "$path" --output "$file"
  echo "⚠ erro desconhecido $code/$subcode registrado em $file" >&2
}
