#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ───────────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0
_pass() { echo "✓ $1"; (( PASS++ )) || true; }
_fail() { echo "✗ $1: $2" >&2; (( FAIL++ )) || true; }
_skip() { echo "- $1 (SKIP)"; (( SKIP++ )) || true; }

# ─── Task 1.2: graph_api ───────────────────────────────────────────────────
test_graph_api_get_me() {
  if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
    _skip "test_graph_api_get_me (sem token)"; return 0
  fi
  # shellcheck source=../lib/graph_api.sh
  source "$(dirname "$0")/../lib/graph_api.sh"
  local response
  response=$(graph_api GET "me?fields=name,id")
  if echo "$response" | jq -e '.id' > /dev/null; then
    _pass "test_graph_api_get_me"
  else
    _fail "test_graph_api_get_me" "expected id in response: $response"; exit 1
  fi
}

# ─── Task 1.3: error-catalog ───────────────────────────────────────────────
test_error_catalog_parse() {
  local catalog
  catalog="$(dirname "$0")/../lib/error-catalog.yaml"
  if python3 -c "
import yaml
with open('$catalog') as f:
    d = yaml.safe_load(f)
assert d['version'] == 1, f'version {d[\"version\"]}'
assert 100 in d['errors'], 'missing 100'
assert 4834011 in d['errors'][100], 'missing 4834011'
assert d['errors'][100][4834011]['fix_fn'] == 'add_field', 'wrong fix_fn'
print('ok')
" 2>&1 | grep -q ok; then
    _pass "test_error_catalog_parse"
  else
    _fail "test_error_catalog_parse" "yaml parse failed"; exit 1
  fi
}

test_error_catalog_count() {
  local catalog
  catalog="$(dirname "$0")/../lib/error-catalog.yaml"
  local count
  count=$(python3 -c "
import yaml
with open('$catalog') as f:
    d = yaml.safe_load(f)
total = sum(len(v) if isinstance(v, dict) else 1 for v in d['errors'].values())
print(total)
")
  if (( count >= 25 )); then
    _pass "test_error_catalog_count (${count} entries)"
  else
    _fail "test_error_catalog_count" "expected >=25, got $count"; exit 1
  fi
}

# ─── Task 1.4: error-resolver ──────────────────────────────────────────────
test_error_resolver_known_error() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  local fix
  fix=$(get_fix_for_error 100 4834011)
  if [[ "$fix" == "add_field:is_adset_budget_sharing_enabled:false" ]]; then
    _pass "test_error_resolver_known_error"
  else
    _fail "test_error_resolver_known_error" "got '$fix'"; exit 1
  fi
}

test_error_resolver_unknown_error() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  local fix
  fix=$(get_fix_for_error 100 9999999)
  if [[ "$fix" == "UNKNOWN" ]]; then
    _pass "test_error_resolver_unknown_error"
  else
    _fail "test_error_resolver_unknown_error" "got '$fix'"; exit 1
  fi
}

# ─── Task 1.5: rollback ────────────────────────────────────────────────────
test_rollback_manifest_add_and_list() {
  local test_dir
  test_dir=$(mktemp -d)
  export MANIFEST_DIR="$test_dir"

  # shellcheck source=../lib/rollback.sh
  source "$(dirname "$0")/../lib/rollback.sh"

  manifest_init "test-run-001" "act_TEST"
  CURRENT_RUN_ID="test-run-001" manifest_add "leadgen_form" "form_123" "test-run-001"
  CURRENT_RUN_ID="test-run-001" manifest_add "campaign" "camp_456" "test-run-001"
  CURRENT_RUN_ID="test-run-001" manifest_add "adset" "as_789" "test-run-001"

  local list
  list=$(manifest_list_for_rollback "test-run-001")
  local count
  count=$(echo "$list" | wc -l | tr -d ' ')

  if [[ "$count" != "3" ]]; then
    _fail "test_rollback_manifest_add_and_list" "expected 3 entries, got $count"; exit 1
  fi

  # Verifica ordem topológica (ad* primeiro, leadgen_form por último em DELETE)
  local first_type
  first_type=$(echo "$list" | head -1 | cut -f2)
  if [[ "$first_type" == "adset" ]]; then
    _pass "test_rollback_manifest_add_and_list"
  else
    _fail "test_rollback_manifest_add_and_list" "expected 'adset' first in rollback, got '$first_type'"; exit 1
  fi

  rm -rf "$test_dir"
}

# ─── Task 1.6: lockfile ────────────────────────────────────────────────────
test_lockfile_acquire_and_release() {
  local test_dir
  test_dir=$(mktemp -d)
  export LOCK_DIR="$test_dir"

  # shellcheck source=../lib/lockfile.sh
  source "$(dirname "$0")/../lib/lockfile.sh"

  acquire_lock "act_TEST" "run-123" || { _fail "test_lockfile_acquire_and_release" "couldn't acquire"; exit 1; }

  # tentativa 2 deve falhar (lock ativo)
  if acquire_lock "act_TEST" "run-456" 2>/dev/null; then
    _fail "test_lockfile_acquire_and_release" "should have blocked 2nd acquire"; exit 1
  fi

  release_lock "act_TEST"
  if [[ ! -f "$test_dir/act_TEST.lock" ]]; then
    _pass "test_lockfile_acquire_and_release"
  else
    _fail "test_lockfile_acquire_and_release" "lock not released"; exit 1
  fi

  rm -rf "$test_dir"
}

test_lockfile_stale_auto_release() {
  local test_dir
  test_dir=$(mktemp -d)
  export LOCK_DIR="$test_dir"
  export STALE_AFTER_SEC=1800

  # shellcheck source=../lib/lockfile.sh
  source "$(dirname "$0")/../lib/lockfile.sh"

  # cria lock com PID falso + timestamp 31min atrás
  local old_ts
  old_ts=$(( $(date +%s) - 1860 ))
  echo "{\"pid\":99999,\"run_id\":\"old\",\"started_at\":$old_ts}" > "$test_dir/act_TEST.lock"

  # acquire deve detectar stale + tomar o lock
  if acquire_lock "act_TEST" "run-new"; then
    _pass "test_lockfile_stale_auto_release"
  else
    _fail "test_lockfile_stale_auto_release" "should take stale lock"; exit 1
  fi

  rm -rf "$test_dir"
}

# ─── Task 1.7: nomenclatura ────────────────────────────────────────────────
test_nomenclatura_ahoy_style() {
  # shellcheck source=../lib/nomenclatura.sh
  source "$(dirname "$0")/../lib/nomenclatura.sh"
  local name
  name=$(gen_name campaign "ahoy-style" produto="curso-excel" objetivo="cadastros" destino="lp" opt="abo" publico="frio")
  if [[ "$name" =~ ^ahoy_[0-9]{8}_curso-excel_cadastros_lp_abo_frio$ ]]; then
    _pass "test_nomenclatura_ahoy_style"
  else
    _fail "test_nomenclatura_ahoy_style" "got '$name'"; exit 1
  fi
}

test_nomenclatura_enxuto() {
  # shellcheck source=../lib/nomenclatura.sh
  source "$(dirname "$0")/../lib/nomenclatura.sh"
  local name
  name=$(gen_name campaign "enxuto" produto="curso" objetivo="vendas")
  if [[ "$name" =~ ^[0-9]{8}-curso-vendas$ ]]; then
    _pass "test_nomenclatura_enxuto"
  else
    _fail "test_nomenclatura_enxuto" "got '$name'"; exit 1
  fi
}

test_nomenclatura_custom() {
  # shellcheck source=../lib/nomenclatura.sh
  source "$(dirname "$0")/../lib/nomenclatura.sh"
  local result
  result=$(apply_template "[{TIPO}][{PRODUTO}][{OPT}]" TIPO=FORMULARIO PRODUTO=PACIENTE-MODELO OPT=AUTO)
  if [[ "$result" == "[FORMULARIO][PACIENTE-MODELO][AUTO]" ]]; then
    _pass "test_nomenclatura_custom"
  else
    _fail "test_nomenclatura_custom" "got '$result'"; exit 1
  fi
}

test_nomenclatura_detect_bracket() {
  # shellcheck source=../lib/nomenclatura.sh
  source "$(dirname "$0")/../lib/nomenclatura.sh"
  local result
  result=$(detect_pattern "[FORMULARIO][PACIENTE-MODELO][AUTO]")
  if [[ "$result" == "[{TOKEN1}][{TOKEN2}][{TOKEN3}]" ]]; then
    _pass "test_nomenclatura_detect_bracket"
  else
    _fail "test_nomenclatura_detect_bracket" "got '$result'"; exit 1
  fi
}

test_nomenclatura_detect_underscore() {
  # shellcheck source=../lib/nomenclatura.sh
  source "$(dirname "$0")/../lib/nomenclatura.sh"
  local result
  result=$(detect_pattern "ahoy_20260319_curso_vendas_lp")
  if [[ "$result" == "{TOKEN1}_{DATE}_{TOKEN2}_{TOKEN3}_{TOKEN4}" ]]; then
    _pass "test_nomenclatura_detect_underscore"
  else
    _fail "test_nomenclatura_detect_underscore" "got '$result'"; exit 1
  fi
}

# ─── Task 1.9: telemetria ──────────────────────────────────────────────────
test_telemetry_log_writes_jsonl() {
  # shellcheck source=../lib/telemetry.sh
  source "$(dirname "$0")/../lib/telemetry.sh"
  local tmpfile
  tmpfile=$(mktemp)
  TELEMETRY_FILE="$tmpfile" telemetry_log "test_event" key1=val1 count=42
  local content
  content=$(cat "$tmpfile")
  if echo "$content" | jq -e '.event == "test_event"' >/dev/null && \
     echo "$content" | jq -e '.key1 == "val1"' >/dev/null; then
    _pass "test_telemetry_log_writes_jsonl"
  else
    _fail "test_telemetry_log_writes_jsonl" "content: $content"; exit 1
  fi
  rm -f "$tmpfile"
}

test_telemetry_opt_out() {
  # shellcheck source=../lib/telemetry.sh
  source "$(dirname "$0")/../lib/telemetry.sh"
  local tmpfile
  tmpfile=$(mktemp)
  META_ADS_NO_TELEMETRY=1 TELEMETRY_FILE="$tmpfile" telemetry_log "should_be_ignored"
  if [[ ! -s "$tmpfile" ]]; then
    _pass "test_telemetry_opt_out"
  else
    _fail "test_telemetry_opt_out" "telemetry opt-out nao respeitado"; exit 1
  fi
  rm -f "$tmpfile"
}

test_feature_flags_default() {
  # shellcheck source=../lib/feature_flags.sh
  source "$(dirname "$0")/../lib/feature_flags.sh"
  local result
  FLAGS_FILE="/nonexistent" result=$(get_flag "missing_flag" "false")
  if [[ "$result" == "false" ]]; then
    _pass "test_feature_flags_default"
  else
    _fail "test_feature_flags_default" "got '$result'"; exit 1
  fi
}

# ─── runner ────────────────────────────────────────────────────────────────
test_graph_api_get_me
test_error_catalog_parse
test_error_catalog_count
test_error_resolver_known_error
test_error_resolver_unknown_error
test_rollback_manifest_add_and_list
test_lockfile_acquire_and_release
test_lockfile_stale_auto_release
test_nomenclatura_ahoy_style
test_nomenclatura_enxuto
test_nomenclatura_custom
test_nomenclatura_detect_bracket
test_nomenclatura_detect_underscore
test_telemetry_log_writes_jsonl
test_telemetry_opt_out
test_feature_flags_default

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
(( FAIL == 0 ))
