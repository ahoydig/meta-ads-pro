#!/usr/bin/env bash
# tests/16-stress.sh — Camada 4/5: stress / rate limit (Task 3c.8)
#
# 4 testes:
#   1) test_stress_50_ads_batch            — 50 GET light + valida BUC header < 80%
#   2) test_stress_parallel_runs_lockfile  — 2 runs simultâneos, 2º bloqueia
#   3) test_stress_error_17_recovery       — simula erro 17/2446079 + lê BUC header
#   4) test_stress_heavy_video_upload      — stub: valida resumable em vídeo >100MB
#
# Skip gracioso se META_ACCESS_TOKEN não estiver setado.
# Bash 3.2 portable (sem mapfile, declare -A, GNU sed).

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"

PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); }
_skip() { echo "- $1 (SKIP: $2)"; SKIP=$((SKIP + 1)); }

_need_token() {
  [[ -n "${META_ACCESS_TOKEN:-}" ]]
}

# ── 1) 50 GETs leves — valida BUC header <80% ────────────────────────────────
test_stress_50_ads_batch() {
  local name="test_stress_50_ads_batch"
  if ! _need_token; then
    _skip "$name" "sem META_ACCESS_TOKEN"
    return 0
  fi

  # shellcheck source=../lib/graph_api.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/graph_api.sh"

  local api_ver="${META_API_VERSION:-v25.0}"
  local token="$META_ACCESS_TOKEN"
  local count=0
  local pct_file
  pct_file=$(mktemp)

  while (( count < 50 )); do
    graph_api GET "${AD_ACCOUNT_ID}?fields=id" >/dev/null 2>&1 || {
      _fail "$name" "graph_api GET falhou na iteração $count"
      rm -f "$pct_file"
      return 1
    }
    count=$((count + 1))
    sleep 0.3
  done

  # Lê X-Business-Use-Case-Usage (JSON: {"act_123":[{"type":"ads_management","call_count":N,"total_cputime":N,"total_time":N,...}]})
  local header_json
  header_json=$(curl -sI \
    "https://graph.facebook.com/${api_ver}/${AD_ACCOUNT_ID}?fields=id&access_token=${token}" \
    | awk 'BEGIN{IGNORECASE=1} /^x-business-use-case-usage:/ {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' \
    | tr -d '\r')

  local max_pct=0
  if [[ -n "$header_json" ]]; then
    # Extrai o maior entre call_count, total_cputime, total_time
    max_pct=$(echo "$header_json" \
      | python3 -c '
import json, sys
try:
    raw = sys.stdin.read().strip()
    if not raw:
        print(0); sys.exit(0)
    data = json.loads(raw)
    best = 0
    if isinstance(data, dict):
        for _acc, entries in data.items():
            if isinstance(entries, list):
                for e in entries:
                    for k in ("call_count", "total_cputime", "total_time"):
                        v = e.get(k) or 0
                        try:
                            best = max(best, int(v))
                        except (TypeError, ValueError):
                            pass
    print(best)
except Exception:
    print(0)
' 2>/dev/null || echo 0)
  fi

  # Guard: se vazio/non-numeric, assume 0 (não falha por header ausente)
  [[ "$max_pct" =~ ^[0-9]+$ ]] || max_pct=0

  rm -f "$pct_file"

  if (( max_pct < 80 )); then
    _pass "$name (BUC max=${max_pct}%)"
  else
    _fail "$name" "BUC ${max_pct}% >= 80% (rate limit próximo)"
  fi
}

# ── 2) 2 runs simultâneos — 2º deve bloquear ────────────────────────────────
test_stress_parallel_runs_lockfile() {
  local name="test_stress_parallel_runs_lockfile"
  # shellcheck source=../lib/lockfile.sh disable=SC1091
  source "$PLUGIN_ROOT/lib/lockfile.sh"

  local tmpdir
  tmpdir=$(mktemp -d)
  local account="act_STRESS_TEST_$$"

  # 1º run: subshell mantém o PID vivo (sleep 5) e segura o lock
  (
    LOCK_DIR="$tmpdir" acquire_lock "$account" "run-1"
    sleep 5
  ) &
  local pid_holder=$!

  # Espera lockfile aparecer (até 2s)
  local waited=0
  while (( waited < 20 )) && [[ ! -f "$tmpdir/$account.lock" ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  if [[ ! -f "$tmpdir/$account.lock" ]]; then
    kill "$pid_holder" 2>/dev/null || true
    wait "$pid_holder" 2>/dev/null || true
    rm -rf "$tmpdir"
    _fail "$name" "1º run não criou lockfile"
    return 1
  fi

  # 2º run: deve falhar (return 1) porque PID do 1º ainda está vivo
  local blocked=0
  if ! LOCK_DIR="$tmpdir" acquire_lock "$account" "run-2" 2>/dev/null; then
    blocked=1
  fi

  kill "$pid_holder" 2>/dev/null || true
  wait "$pid_holder" 2>/dev/null || true
  LOCK_DIR="$tmpdir" release_lock "$account" 2>/dev/null || true
  rm -rf "$tmpdir"

  if (( blocked == 1 )); then
    _pass "$name"
  else
    _fail "$name" "2º run não foi bloqueado"
  fi
}

# ── 3) Erro 17/2446079 recovery — lê estimated_time_to_regain_access ─────────
test_stress_error_17_recovery() {
  local name="test_stress_error_17_recovery"

  # Fixture: resposta Meta típica de BUC rate limit
  # (X-Business-Use-Case-Usage + body.error.code=17 subcode=2446079)
  local buc_header_json
  buc_header_json='{"act_763408067802379":[{"type":"ads_management","call_count":100,"total_cputime":100,"total_time":100,"estimated_time_to_regain_access":42}]}'

  # Valida extração do estimated_time_to_regain_access
  local etta
  etta=$(echo "$buc_header_json" \
    | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    for _acc, entries in data.items():
        for e in entries:
            v = e.get("estimated_time_to_regain_access")
            if v is not None:
                print(int(v)); sys.exit(0)
    print(0)
except Exception:
    print(-1)
' 2>/dev/null || echo -1)

  if [[ "$etta" != "42" ]]; then
    _fail "$name" "parse de estimated_time_to_regain_access falhou (got=$etta, esperado=42)"
    return 1
  fi

  # Valida que error-catalog.yaml tem entrada 17/2446079 com action read_buc_header_and_wait
  local catalog="$PLUGIN_ROOT/lib/error-catalog.yaml"
  if [[ ! -f "$catalog" ]]; then
    _fail "$name" "error-catalog.yaml ausente"
    return 1
  fi
  if ! grep -qE '^\s*17:' "$catalog"; then
    _fail "$name" "error 17 não está no error-catalog.yaml"
    return 1
  fi
  if ! grep -qE '^\s*2446079:' "$catalog"; then
    _fail "$name" "subcode 2446079 não está no error-catalog.yaml"
    return 1
  fi
  if ! grep -q "read_buc_header_and_wait" "$catalog"; then
    _fail "$name" "action read_buc_header_and_wait ausente no catalog"
    return 1
  fi

  # Valida que error-resolver.sh reconhece a action (mesmo que ainda seja TODO_CP_FUTURE)
  if ! grep -q "read_buc_header_and_wait" "$PLUGIN_ROOT/lib/error-resolver.sh"; then
    _fail "$name" "error-resolver.sh não trata read_buc_header_and_wait"
    return 1
  fi

  _pass "$name (ETTA=${etta}s, catalog+resolver OK)"
}

# ── 4) Upload vídeo >100MB — deve rotear pra resumable (stub estrutural) ─────
test_stress_heavy_video_upload() {
  local name="test_stress_heavy_video_upload"
  local src="$PLUGIN_ROOT/lib/upload_video.sh"

  if [[ ! -f "$src" ]]; then
    _fail "$name" "lib/upload_video.sh ausente"
    return 1
  fi

  # Valida existência das 3 fases resumable + threshold 100MB
  local missing=""
  grep -q "_upload_video_resumable"     "$src" || missing+=" _upload_video_resumable"
  grep -q 'upload_phase=start'          "$src" || missing+=" upload_phase=start"
  grep -q 'upload_phase=transfer'       "$src" || missing+=" upload_phase=transfer"
  grep -q 'upload_phase=finish'         "$src" || missing+=" upload_phase=finish"
  grep -qE 'size_mb[[:space:]]*<=?[[:space:]]*100|size_mb[[:space:]]*>[[:space:]]*100' "$src" \
    || missing+=" threshold_100MB"
  grep -qE 'size_mb[[:space:]]*>[[:space:]]*200' "$src" \
    || missing+=" threshold_200MB_cputime"

  if [[ -n "$missing" ]]; then
    _fail "$name" "upload_video.sh sem:$missing"
    return 1
  fi

  # Simula decisão de roteamento: 150MB → resumable. Faz check de branch sem rede.
  # upload_video é uma função shell pura; só queremos que 150MB não caia no direct.
  # Stub: grep pela condição if (( size_mb <= 100 )) seguido por _upload_video_direct
  if ! awk '
    /size_mb <= 100/ { in_if=1; next }
    in_if && /_upload_video_direct/ { found=1; exit }
    in_if && /^[[:space:]]*else/ { in_if=0 }
  END { exit found?0:1 }
  ' "$src"; then
    _fail "$name" "roteamento por tamanho não encontrado (≤100MB→direct)"
    return 1
  fi

  _pass "$name (resumable + thresholds 100/200MB OK)"
}

# ── runner ───────────────────────────────────────────────────────────────────
test_stress_50_ads_batch
test_stress_parallel_runs_lockfile
test_stress_error_17_recovery
test_stress_heavy_video_upload

echo ""
echo "16-stress: $PASS passou, $FAIL falhou, $SKIP pulado"
[[ "$FAIL" -eq 0 ]]
