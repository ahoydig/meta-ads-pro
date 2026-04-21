#!/usr/bin/env bash
# lockfile.sh — lock por ad_account pra evitar race conditions

set -euo pipefail

LOCK_DIR="${LOCK_DIR:-${HOME}/.claude/meta-ads-pro/current}"
STALE_AFTER_SEC="${STALE_AFTER_SEC:-1800}"  # 30min
mkdir -p "$LOCK_DIR"

_lock_file() {
  echo "$LOCK_DIR/$1.lock"
}

acquire_lock() {
  local account="$1" run_id="$2"
  local file
  file=$(_lock_file "$account")

  if [[ -f "$file" ]]; then
    local pid age now
    pid=$(jq -r '.pid // empty' "$file" 2>/dev/null || echo "")
    age=$(jq -r '.started_at // 0' "$file" 2>/dev/null || echo "0")
    now=$(date +%s)

    # Normaliza: se jq retornou "null" ou vazio, trata como stale
    if [[ -z "$pid" || "$pid" == "null" ]]; then
      echo "⚠ lock malformado, removendo" >&2
    elif (( now - age > STALE_AFTER_SEC )); then
      # Stale por idade, independente do PID estar vivo
      echo "⚠ lock stale (>${STALE_AFTER_SEC}s), removendo" >&2
    elif kill -0 "$pid" 2>/dev/null; then
      # PID vivo e lock recente → bloqueia
      echo "❌ lock ativo por PID $pid desde $age. Aguarde ou rode '/meta-ads-doctor --release-lock'" >&2
      return 1
    else
      # PID morto → stale
      echo "⚠ lock órfão (PID $pid morto), removendo" >&2
    fi
  fi

  local now
  now=$(date +%s)
  jq -n --argjson pid "$$" --arg rid "$run_id" --argjson ts "$now" \
    '{pid:$pid,run_id:$rid,started_at:$ts}' > "$file"
}

release_lock() {
  local account="$1"
  rm -f "$(_lock_file "$account")"
}

# handler pra SIGINT/SIGTERM
setup_lock_cleanup() {
  local account="$1"
  # shellcheck disable=SC2064
  trap "release_lock '$account'" INT TERM EXIT
}
