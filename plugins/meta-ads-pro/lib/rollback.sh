#!/usr/bin/env bash
# rollback.sh — manifest transacional + rollback topológico

set -euo pipefail

MANIFEST_DIR="${MANIFEST_DIR:-${HOME}/.claude/meta-ads-pro/current}"
mkdir -p "$MANIFEST_DIR"

# Ordem topológica de DELETE (prioridade — menor primeiro = deleta primeiro):
# 1. ads
# 2. adcreatives, dark_posts
# 3. adimages
# 4. adsets
# 5. campaigns
# 6. leadgen_forms
# (prioridade gerenciada em lib/_py/manifest.py :: PRIORITY dict)

manifest_path() {
  echo "$MANIFEST_DIR/$1.json"
}

manifest_init() {
  local run_id="$1" account="$2"
  local file
  file=$(manifest_path "$run_id")
  python3 "$(dirname "${BASH_SOURCE[0]}")/_py/manifest.py" init \
    --file "$file" --run-id "$run_id" --account "$account"
}

manifest_add() {
  local type="$1" id="$2" run_id="${3:-${CURRENT_RUN_ID:?}}"
  local file
  file=$(manifest_path "$run_id")
  python3 "$(dirname "${BASH_SOURCE[0]}")/_py/manifest.py" add \
    --file "$file" --type "$type" --id "$id"
}

# Retorna linhas tab-separadas: priority\ttype\tid ordenadas por priority asc
manifest_list_for_rollback() {
  local run_id="$1"
  local file
  file=$(manifest_path "$run_id")
  [[ -f "$file" ]] || { echo "manifest não encontrado: $file" >&2; return 1; }
  python3 "$(dirname "${BASH_SOURCE[0]}")/_py/manifest.py" list --file "$file"
}

# Executa rollback respeitando topologia
rollback_run() {
  local run_id="$1"
  local list
  list=$(manifest_list_for_rollback "$run_id")
  local deleted=0 preserved=0

  # source graph_api se disponível (permite teste standalone)
  if [[ -f "$(dirname "${BASH_SOURCE[0]}")/graph_api.sh" ]] && [[ "${ROLLBACK_MOCK:-0}" != "1" ]]; then
    # shellcheck source=/dev/null
    source "$(dirname "${BASH_SOURCE[0]}")/graph_api.sh"
  fi

  # Guard contra manifest vazio (nada criado ainda)
  if [[ -z "$list" ]]; then
    echo "rollback: manifest vazio, nada a fazer" >&2
    # Move manifest pra history (run que abortou antes de criar qualquer objeto)
    local file history_dir
    file=$(manifest_path "$run_id")
    history_dir="${HOME}/.claude/meta-ads-pro/history"
    mkdir -p "$history_dir"
    [[ -f "$file" ]] && mv "$file" "$history_dir/"
    return 0
  fi

  while IFS=$'\t' read -r priority type obj_id; do
    # Skip linhas vazias
    [[ -z "$priority" && -z "$type" && -z "$obj_id" ]] && continue
    echo "🗑  deletando $type/$obj_id (priority $priority)" >&2
    if [[ "${ROLLBACK_MOCK:-0}" == "1" ]]; then
      (( deleted++ )) || true
    else
      local retry=0 delete_ok=0
      # Lead gen forms não suportam DELETE direto — usar status=ARCHIVED via page token
      if [[ "$type" == "leadgen_form" ]]; then
        local page_token_leadform
        page_token_leadform=$(graph_api GET "${PAGE_ID:-}?fields=access_token" 2>/dev/null | jq -r '.access_token // empty')
        if [[ -n "$page_token_leadform" ]]; then
          if curl -sS -X POST "https://graph.facebook.com/${META_API_VERSION:-v25.0}/$obj_id" \
            -d "status=ARCHIVED" -d "access_token=$page_token_leadform" 2>/dev/null | jq -e '.success == true' >/dev/null; then
            echo "    ✓ lead form ARCHIVED (Meta não permite DELETE direto)" >&2
            (( deleted++ )) || true
            continue
          fi
        fi
        echo "    ⚠ lead form não pôde ser archived (sem page token?) — preservando" >&2
        (( preserved++ )) || true
        continue
      fi
      while (( retry < 3 )); do
        if GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$obj_id" 2>/dev/null; then
          (( deleted++ )) || true; delete_ok=1; break
        fi
        local err_code
        err_code=$(graph_api GET "$obj_id?fields=id" 2>&1 | jq -r '.error.code // empty')
        # 404 = já deletado (idempotente)
        if [[ "$err_code" == "" ]]; then
          (( deleted++ )) || true; delete_ok=1; break
        fi
        # 613/80004 = rate limit, retry com delay
        if [[ "$err_code" == "613" || "$err_code" == "80004" ]]; then
          (( retry++ )) || true; sleep 60; continue
        fi
        # qualquer outro = preserva
        break
      done
      (( delete_ok == 0 )) && (( preserved++ )) || true
    fi
  done <<< "$list"

  echo "rollback: $deleted deletados, $preserved preservados" >&2

  # Move manifest pra failures/ (se preservados) ou history/ (se tudo ok)
  local file failures_dir history_dir
  file=$(manifest_path "$run_id")
  if (( preserved > 0 )); then
    failures_dir="${HOME}/.claude/meta-ads-pro/failures"
    mkdir -p "$failures_dir"
    mv "$file" "$failures_dir/"
  else
    history_dir="${HOME}/.claude/meta-ads-pro/history"
    mkdir -p "$history_dir"
    mv "$file" "$history_dir/"
  fi
}
