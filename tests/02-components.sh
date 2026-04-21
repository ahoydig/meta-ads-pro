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

# ─── CP2a.fix: apply_fix_to_body (apply-retry glue pro resolver) ──────────
test_apply_fix_to_body_add_field_bool() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  local out
  out=$(apply_fix_to_body '{"name":"x"}' 'add_field:is_adset_budget_sharing_enabled:false')
  if echo "$out" | jq -e '.is_adset_budget_sharing_enabled == false and .name == "x"' >/dev/null; then
    _pass "test_apply_fix_to_body_add_field_bool"
  else
    _fail "test_apply_fix_to_body_add_field_bool" "got '$out'"; exit 1
  fi
}

test_apply_fix_to_body_add_field_int() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  local out
  out=$(apply_fix_to_body '{"a":1}' 'add_field:count:42')
  if echo "$out" | jq -e '.count == 42 and .a == 1' >/dev/null; then
    _pass "test_apply_fix_to_body_add_field_int"
  else
    _fail "test_apply_fix_to_body_add_field_int" "got '$out'"; exit 1
  fi
}

test_apply_fix_to_body_add_nested_int() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  local out
  out=$(apply_fix_to_body '{"targeting":{"geo_locations":{"countries":["BR"]}}}' \
    'add_nested:targeting.targeting_automation.advantage_audience:0')
  if echo "$out" | jq -e '.targeting.targeting_automation.advantage_audience == 0 and .targeting.geo_locations.countries[0] == "BR"' >/dev/null; then
    _pass "test_apply_fix_to_body_add_nested_int"
  else
    _fail "test_apply_fix_to_body_add_nested_int" "got '$out'"; exit 1
  fi
}

test_apply_fix_to_body_add_field_string() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  local out
  out=$(apply_fix_to_body '{}' 'add_field:status:PAUSED')
  if echo "$out" | jq -e '.status == "PAUSED"' >/dev/null; then
    _pass "test_apply_fix_to_body_add_field_string"
  else
    _fail "test_apply_fix_to_body_add_field_string" "got '$out'"; exit 1
  fi
}

test_resolve_error_exports_resolver_fix() {
  # shellcheck source=../lib/error-resolver.sh
  source "$(dirname "$0")/../lib/error-resolver.sh"
  unset RESOLVER_FIX || true
  local rc=0
  resolve_error 100 4834011 '{"error":{"code":100}}' POST "act_X/campaigns" '{}' >/dev/null 2>&1 || rc=$?
  if (( rc == 2 )) && [[ "${RESOLVER_FIX:-}" == "add_field:is_adset_budget_sharing_enabled:false" ]]; then
    _pass "test_resolve_error_exports_resolver_fix"
  else
    _fail "test_resolve_error_exports_resolver_fix" "rc=$rc RESOLVER_FIX='${RESOLVER_FIX:-}'"; exit 1
  fi
}

# ─── Task 2c.1.1: media_hash ───────────────────────────────────────────────
test_media_hash_length() {
  local tmp h
  tmp=$(mktemp); echo "teste" > "$tmp"
  h=$(python3 "$(dirname "$0")/../lib/_py/media_hash.py" "$tmp")
  rm -f "$tmp"
  if [[ ${#h} -eq 64 ]]; then
    _pass "test_media_hash_length"
  else
    _fail "test_media_hash_length" "expected 64-char hex, got '${h}' (len=${#h})"; exit 1
  fi
}

test_media_hash_stable() {
  # Mesmo conteúdo em arquivos diferentes → mesmo hash (determinístico)
  local a b ha hb
  a=$(mktemp); b=$(mktemp)
  printf "conteudo fixo\n" > "$a"
  printf "conteudo fixo\n" > "$b"
  ha=$(python3 "$(dirname "$0")/../lib/_py/media_hash.py" "$a")
  hb=$(python3 "$(dirname "$0")/../lib/_py/media_hash.py" "$b")
  rm -f "$a" "$b"
  if [[ "$ha" == "$hb" ]]; then
    _pass "test_media_hash_stable"
  else
    _fail "test_media_hash_stable" "hashes diferentes pra mesmo conteúdo"; exit 1
  fi
}

test_media_hash_missing_file() {
  local rc
  python3 "$(dirname "$0")/../lib/_py/media_hash.py" /nonexistent/path 2>/dev/null || rc=$?
  if [[ "${rc:-0}" -eq 1 ]]; then
    _pass "test_media_hash_missing_file"
  else
    _fail "test_media_hash_missing_file" "expected exit 1, got ${rc:-0}"; exit 1
  fi
}

# ─── Task 2c.3.1: copy_prompt_builder ──────────────────────────────────────
test_copy_prompt_builder_headline() {
  local prompt
  prompt=$(python3 "$(dirname "$0")/../lib/_py/copy_prompt_builder.py" \
    --field headline --count 3 --objective OUTCOME_LEADS --product "curso X")
  if [[ "$prompt" == *"3 variações"* && "$prompt" == *"curso X"* && "$prompt" == *"OUTCOME_LEADS"* ]]; then
    _pass "test_copy_prompt_builder_headline"
  else
    _fail "test_copy_prompt_builder_headline" "missing expected tokens"; exit 1
  fi
}

test_copy_prompt_builder_voice_file() {
  local voice prompt
  voice=$(mktemp)
  printf "voz: direta, empírica\n" > "$voice"
  prompt=$(python3 "$(dirname "$0")/../lib/_py/copy_prompt_builder.py" \
    --field primary_text --count 2 --objective OUTCOME_AWARENESS \
    --product "serviço Y" --voice-file "$voice")
  rm -f "$voice"
  if [[ "$prompt" == *"Voz da marca"* && "$prompt" == *"direta, empírica"* ]]; then
    _pass "test_copy_prompt_builder_voice_file"
  else
    _fail "test_copy_prompt_builder_voice_file" "voice guidance não injetado"; exit 1
  fi
}

test_copy_prompt_builder_invalid_field() {
  local rc
  python3 "$(dirname "$0")/../lib/_py/copy_prompt_builder.py" \
    --field bogus --objective X --product Y 2>/dev/null || rc=$?
  if [[ "${rc:-0}" -eq 2 ]]; then
    _pass "test_copy_prompt_builder_invalid_field"
  else
    _fail "test_copy_prompt_builder_invalid_field" "expected exit 2, got ${rc:-0}"; exit 1
  fi
}

# ─── Task 2c.3.5: claude_invoke_api ────────────────────────────────────────
test_claude_invoke_api_missing_key() {
  local output rc
  output=$(ANTHROPIC_API_KEY="" python3 "$(dirname "$0")/../lib/_py/claude_invoke_api.py" "prompt" 2>/dev/null) || rc=$?
  if [[ "$output" == "[]" && "${rc:-0}" -eq 1 ]]; then
    _pass "test_claude_invoke_api_missing_key"
  else
    _fail "test_claude_invoke_api_missing_key" "output='$output' rc='${rc:-0}'"; exit 1
  fi
}

test_claude_invoke_api_invalid_max_tokens() {
  # M1: META_ADS_COPY_MAX_TOKENS inválido não deve crashar — volta pro default 1024
  local stderr_output rc
  stderr_output=$(ANTHROPIC_API_KEY="" META_ADS_COPY_MAX_TOKENS="abc" \
    python3 "$(dirname "$0")/../lib/_py/claude_invoke_api.py" "prompt" 2>&1 >/dev/null) || rc=$?
  # exit 1 (API key ausente) é esperado — queremos só garantir que não crashou com ValueError
  if [[ "${rc:-0}" -eq 1 ]] && [[ "$stderr_output" != *"Traceback"* ]]; then
    _pass "test_claude_invoke_api_invalid_max_tokens"
  else
    _fail "test_claude_invoke_api_invalid_max_tokens" "rc='${rc:-0}' stderr='$stderr_output'"; exit 1
  fi
}

test_copy_prompt_builder_voice_missing() {
  # M3: voice-file ausente avisa em stderr mas não crasha
  local stderr_output rc
  stderr_output=$(python3 "$(dirname "$0")/../lib/_py/copy_prompt_builder.py" \
    --field headline --count 2 --objective OUTCOME_LEADS --product X \
    --voice-file /nonexistent/voice.md 2>&1 >/dev/null) || rc=$?
  if [[ "${rc:-0}" -eq 0 && "$stderr_output" == *"voice-file não aplicado"* ]]; then
    _pass "test_copy_prompt_builder_voice_missing"
  else
    _fail "test_copy_prompt_builder_voice_missing" "rc='${rc:-0}' stderr='$stderr_output'"; exit 1
  fi
}

test_claude_invoke_api_usage() {
  local rc
  python3 "$(dirname "$0")/../lib/_py/claude_invoke_api.py" >/dev/null 2>&1 || rc=$?
  if [[ "${rc:-0}" -eq 2 ]]; then
    _pass "test_claude_invoke_api_usage"
  else
    _fail "test_claude_invoke_api_usage" "expected exit 2, got ${rc:-0}"; exit 1
  fi
}

# ─── Task 3b.2.2: dry_run_manifest ─────────────────────────────────────────
test_dry_run_manifest_append() {
  local tmp_dir entry file
  tmp_dir=$(mktemp -d)
  DRY_RUN_DIR="$tmp_dir" python3 "$(dirname "$0")/../lib/_py/dry_run_manifest.py" \
    --method POST --path "act_x/campaigns" \
    --body '{"name":"test"}' --ghost-id "DRY_RUN_1234"
  file=$(find "$tmp_dir" -name "*.jsonl" | head -1)
  if [[ -z "$file" ]]; then
    rm -rf "$tmp_dir"
    _fail "test_dry_run_manifest_append" "nenhum jsonl escrito"; exit 1
  fi
  entry=$(cat "$file")
  rm -rf "$tmp_dir"
  if echo "$entry" | jq -e '.ghost_id == "DRY_RUN_1234" and .method == "POST" and .body.name == "test"' >/dev/null; then
    _pass "test_dry_run_manifest_append"
  else
    _fail "test_dry_run_manifest_append" "schema invalido: $entry"; exit 1
  fi
}

test_dry_run_manifest_body_string() {
  local tmp_dir entry file
  tmp_dir=$(mktemp -d)
  # body não-JSON: deve ser preservado como string
  DRY_RUN_DIR="$tmp_dir" python3 "$(dirname "$0")/../lib/_py/dry_run_manifest.py" \
    --method DELETE --path "abc123" \
    --body 'form-encoded=raw' --ghost-id "DRY_RUN_5678"
  file=$(find "$tmp_dir" -name "*.jsonl" | head -1)
  entry=$(cat "$file")
  rm -rf "$tmp_dir"
  if echo "$entry" | jq -e '.body | type == "string"' >/dev/null; then
    _pass "test_dry_run_manifest_body_string"
  else
    _fail "test_dry_run_manifest_body_string" "body não é string: $entry"; exit 1
  fi
}

# ─── Task 3b.1.1: import_existing ──────────────────────────────────────────
test_import_existing_usage() {
  local rc
  python3 "$(dirname "$0")/../lib/_py/import_existing.py" 2>/dev/null || rc=$?
  # argparse retorna 2 em args obrigatórios faltando
  if [[ "${rc:-0}" -eq 2 ]]; then
    _pass "test_import_existing_usage"
  else
    _fail "test_import_existing_usage" "expected exit 2, got ${rc:-0}"; exit 1
  fi
}

test_import_existing_smoke() {
  # Teste vivo contra Graph API; pula sem token
  if [[ -z "${META_ACCESS_TOKEN:-}" || -z "${AD_ACCOUNT_ID:-}" ]]; then
    _skip "test_import_existing_smoke (sem META_ACCESS_TOKEN/AD_ACCOUNT_ID)"; return 0
  fi
  local tmp_dir out
  tmp_dir=$(mktemp -d)
  if out=$(python3 "$(dirname "$0")/../lib/_py/import_existing.py" \
      --account "$AD_ACCOUNT_ID" --token "$META_ACCESS_TOKEN" \
      --out "$tmp_dir" 2>/dev/null); then
    if [[ -f "$out" ]] && jq -e '.summary.campaigns | type == "number"' "$out" >/dev/null; then
      rm -rf "$tmp_dir"
      _pass "test_import_existing_smoke"
    else
      rm -rf "$tmp_dir"
      _fail "test_import_existing_smoke" "schema inválido em $out"; exit 1
    fi
  else
    rm -rf "$tmp_dir"
    _fail "test_import_existing_smoke" "import falhou"; exit 1
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
test_apply_fix_to_body_add_field_bool
test_apply_fix_to_body_add_field_int
test_apply_fix_to_body_add_nested_int
test_apply_fix_to_body_add_field_string
test_resolve_error_exports_resolver_fix
test_media_hash_length
test_media_hash_stable
test_media_hash_missing_file
test_copy_prompt_builder_headline
test_copy_prompt_builder_voice_file
test_copy_prompt_builder_invalid_field
test_copy_prompt_builder_voice_missing
test_claude_invoke_api_missing_key
test_claude_invoke_api_usage
test_claude_invoke_api_invalid_max_tokens
test_dry_run_manifest_append
test_dry_run_manifest_body_string
test_import_existing_usage
test_import_existing_smoke

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
(( FAIL == 0 ))
