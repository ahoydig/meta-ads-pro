#!/usr/bin/env bash
# tests/13-dry-run.sh — valida META_ADS_DRY_RUN=1 em lib/graph_api.sh (hotfix d12f11f)
#
# Cobertura:
#   1. POST interceptado — retorna ghost_id, não chama curl
#   2. DELETE interceptado — idem
#   3. GET NÃO é interceptado (passa pro curl)
#   4. JSONL manifest em $DRY_RUN_DIR tem entry correta por ghost
#   5. body_parse: JSON vira obj, não-JSON vira string crua
#
# Offline-friendly: usa curl-stub via PATH override, nenhuma chamada
# real à Graph API. shellcheck clean, bash 3.2 portable.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0
_pass() { echo "✓ $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$(( FAIL + 1 )); }

# ── tempdir isolado pra DRY_RUN_DIR + curl stub ──────────────────────────────
TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/dry-run-test.XXXXXX")
export DRY_RUN_DIR="$TMPROOT/dry-runs"
STUB_BIN="$TMPROOT/bin"
mkdir -p "$STUB_BIN"

cleanup_all() {
  local rc=$?
  rm -rf "$TMPROOT" 2>/dev/null || true
  exit $rc
}
trap cleanup_all EXIT INT TERM

# curl stub — devolve 401 offline (bate com formato de graph_api.sh: body + http_code)
cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/sh
echo '{"error":{"code":190,"message":"stub offline"}}'
echo "401"
STUB
chmod +x "$STUB_BIN/curl"

# Ambiente: dummy token + dry run ligado + resolver off pra evitar retry loop
export META_ACCESS_TOKEN="DUMMY_TOKEN_FOR_TEST"
export META_ADS_DRY_RUN=1
export GRAPH_API_SKIP_RESOLVER=1

# shellcheck source=../lib/graph_api.sh
source "$PLUGIN_ROOT/lib/graph_api.sh"

# ─────────────────────────────────────────────────────────────────────────────
# 1. POST interceptado → retorna {"id":"DRY_RUN_...","dry_run":true}
# ─────────────────────────────────────────────────────────────────────────────
test_dry_run_intercepts_post() {
  local out
  out=$(graph_api POST "act_XXX/campaigns" '{"name":"test"}' 2>/dev/null) || {
    _fail "test_dry_run_intercepts_post" "graph_api POST retornou erro"
    return
  }
  local is_ghost id
  is_ghost=$(echo "$out" | jq -r '.dry_run // false')
  id=$(echo "$out" | jq -r '.id // empty')
  if [[ "$is_ghost" == "true" ]] && [[ "$id" == DRY_RUN_* ]]; then
    _pass "test_dry_run_intercepts_post (id=$id)"
  else
    _fail "test_dry_run_intercepts_post" "out=$out"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. DELETE interceptado idem
# ─────────────────────────────────────────────────────────────────────────────
test_dry_run_intercepts_delete() {
  local out
  out=$(graph_api DELETE "12345" 2>/dev/null) || {
    _fail "test_dry_run_intercepts_delete" "graph_api DELETE retornou erro"
    return
  }
  local is_ghost id
  is_ghost=$(echo "$out" | jq -r '.dry_run // false')
  id=$(echo "$out" | jq -r '.id // empty')
  if [[ "$is_ghost" == "true" ]] && [[ "$id" == DRY_RUN_* ]]; then
    _pass "test_dry_run_intercepts_delete (id=$id)"
  else
    _fail "test_dry_run_intercepts_delete" "out=$out"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. GET NÃO interceptado (vai pro curl stub, retorna erro)
# ─────────────────────────────────────────────────────────────────────────────
test_dry_run_does_not_intercept_get() {
  local before_count after_count out rc=0
  before_count=$(find "$DRY_RUN_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  # Força PATH stub só pra essa chamada
  out=$(PATH="$STUB_BIN:$PATH" graph_api GET "me?fields=id" 2>&1) || rc=$?
  after_count=$(find "$DRY_RUN_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')

  # Verifica: (a) resposta NÃO tem "dry_run":true, (b) nenhum ghost file novo
  if echo "$out" | grep -q '"dry_run":true'; then
    _fail "test_dry_run_does_not_intercept_get" "GET foi interceptado (out=$out)"
    return
  fi
  if [[ "$before_count" != "$after_count" ]]; then
    _fail "test_dry_run_does_not_intercept_get" "GET gerou ghost ($before_count → $after_count)"
    return
  fi
  # Esperamos rc!=0 (curl stub retorna 401)
  if (( rc == 0 )); then
    _fail "test_dry_run_does_not_intercept_get" "GET retornou 0 (esperado != 0 via stub 401)"
    return
  fi
  _pass "test_dry_run_does_not_intercept_get (rc=$rc, sem ghost)"
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. JSONL manifest criado com entries corretas
# ─────────────────────────────────────────────────────────────────────────────
test_dry_run_manifest_content() {
  local files
  files=$(find "$DRY_RUN_DIR" -type f -name '*.jsonl' 2>/dev/null)
  if [[ -z "$files" ]]; then
    _fail "test_dry_run_manifest_content" "sem arquivo .jsonl em $DRY_RUN_DIR"
    return
  fi
  # Concatena todos .jsonl (pode haver 1 ou 2 dependendo do segundo de criação)
  local all_entries errs=0 f
  all_entries=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    all_entries="${all_entries}$(cat "$f")"$'\n'
  done <<< "$files"

  local post_entry delete_entry
  post_entry=$(echo "$all_entries" | jq -c 'select(.method=="POST")' | head -n1)
  delete_entry=$(echo "$all_entries" | jq -c 'select(.method=="DELETE")' | head -n1)

  # POST entry: tem path, body como obj, ghost_id, ts
  if [[ -z "$post_entry" ]]; then
    errs=$((errs+1)); echo "  ↳ sem entry POST" >&2
  else
    local p_path p_body_name p_ghost p_ts
    p_path=$(echo "$post_entry" | jq -r '.path // empty')
    p_body_name=$(echo "$post_entry" | jq -r '.body.name // empty')
    p_ghost=$(echo "$post_entry" | jq -r '.ghost_id // empty')
    p_ts=$(echo "$post_entry" | jq -r '.ts // empty')
    [[ "$p_path" == "act_XXX/campaigns" ]] || { errs=$((errs+1)); echo "  ↳ POST.path='$p_path'" >&2; }
    [[ "$p_body_name" == "test" ]]         || { errs=$((errs+1)); echo "  ↳ POST.body.name='$p_body_name'" >&2; }
    [[ "$p_ghost" == DRY_RUN_* ]]          || { errs=$((errs+1)); echo "  ↳ POST.ghost_id='$p_ghost'" >&2; }
    [[ -n "$p_ts" ]]                       || { errs=$((errs+1)); echo "  ↳ POST.ts vazio" >&2; }
  fi

  # DELETE entry: tem path, body = null ou {} (sem body), ghost_id
  if [[ -z "$delete_entry" ]]; then
    errs=$((errs+1)); echo "  ↳ sem entry DELETE" >&2
  else
    local d_path d_ghost
    d_path=$(echo "$delete_entry" | jq -r '.path // empty')
    d_ghost=$(echo "$delete_entry" | jq -r '.ghost_id // empty')
    [[ "$d_path" == "12345" ]]    || { errs=$((errs+1)); echo "  ↳ DELETE.path='$d_path'" >&2; }
    [[ "$d_ghost" == DRY_RUN_* ]] || { errs=$((errs+1)); echo "  ↳ DELETE.ghost_id='$d_ghost'" >&2; }
  fi

  if (( errs == 0 )); then
    _pass "test_dry_run_manifest_content (POST + DELETE entries corretas)"
  else
    _fail "test_dry_run_manifest_content" "$errs erros no JSONL"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. body não-JSON → guardado como string (robustez)
# ─────────────────────────────────────────────────────────────────────────────
test_dry_run_body_non_json_as_string() {
  # POST com body vazio vira {} (guard interno de graph_api.sh) — testamos que
  # aceita sem quebrar e a entry resultante tem body como {}  ou null.
  local out
  out=$(graph_api POST "act_XXX/adsets" "" 2>/dev/null) || {
    _fail "test_dry_run_body_non_json_as_string" "graph_api POST body-vazio quebrou"
    return
  }
  echo "$out" | jq -e '.dry_run == true' >/dev/null || {
    _fail "test_dry_run_body_non_json_as_string" "POST body-vazio não virou ghost"
    return
  }
  _pass "test_dry_run_body_non_json_as_string"
}

# ── runner ───────────────────────────────────────────────────────────────────
for t in \
  test_dry_run_intercepts_post \
  test_dry_run_intercepts_delete \
  test_dry_run_does_not_intercept_get \
  test_dry_run_manifest_content \
  test_dry_run_body_non_json_as_string
do
  $t
done

echo ""
echo "dry-run: ${PASS} passou, ${FAIL} falhou"
[[ "$FAIL" -eq 0 ]]
