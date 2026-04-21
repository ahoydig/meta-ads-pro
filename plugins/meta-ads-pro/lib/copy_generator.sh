#!/usr/bin/env bash
# copy_generator.sh — gera variações de copy via Claude multimodal + humanizer
#
# 3 modos de invocação (prioridade):
#   1. META_ADS_COPY_MOCK=1            → retorna array dummy (testes isolados)
#   2. ANTHROPIC_API_KEY setado        → lib/_py/claude_invoke_api.py (CI)
#   3. Dentro do Claude Code           → signal file CLAUDE_CODE_INVOKE_SUBAGENT
#                                        que o orchestrator intercepta e
#                                        responde via Task tool
#
# Todos os 3 modos retornam JSON array; pipeline final passa pelo humanizer.

set -euo pipefail

_COPY_GEN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_COPY_GEN_PY_DIR="${_COPY_GEN_LIB_DIR}/_py"

# gen_copy <field> <count> <image> <objective> <audience> [voice_file] [product]
#   field:      headline | description | primary_text
#   count:      2..5
#   image:      path (pra context multimodal) ou vazio
#   objective:  OUTCOME_LEADS | OUTCOME_SALES | ...
#   audience:   descrição textual (pode ser vazio)
#   voice_file: path pro voice profile (opcional)
#   product:    nome/descrição do produto
#
# stdout: JSON array de strings (humanizadas).
gen_copy() {
  local field="$1" count="$2" image="$3"
  local objective="$4" audience="$5"
  local voice_file="${6:-}" product="${7:-}"

  # Validação defensiva
  case "$field" in
    headline|description|primary_text) ;;
    *)
      echo "gen_copy: field inválido '$field' (use headline|description|primary_text)" >&2
      return 1
      ;;
  esac
  [[ "$count" =~ ^[2-5]$ ]] || {
    echo "gen_copy: count precisa ser 2..5 (got '$count')" >&2
    return 1
  }

  # 1. Monta prompt via Python builder (stdin-safe, nunca heredoc)
  local prompt
  prompt=$(python3 "${_COPY_GEN_PY_DIR}/copy_prompt_builder.py" \
    --field "$field" --count "$count" --image-path "$image" \
    --objective "$objective" --audience "$audience" \
    --voice-file "$voice_file" --product "$product")

  # 2. Invoca Claude pelo canal disponível
  local raw_json
  raw_json=$(claude_invoke "$prompt" "$count" "$field") || raw_json="[]"

  # 3. Valida JSON array
  if ! echo "$raw_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "copy_generator: resposta não é JSON array — $raw_json" >&2
    return 1
  fi

  # 4. Humanizer pipeline (silent fallback pra raw em falha)
  # shellcheck source=/dev/null
  source "${_COPY_GEN_LIB_DIR}/humanizer-bridge.sh"
  humanize_array "$raw_json" "$voice_file"
}

# ─── Contrato claude_invoke ────────────────────────────────────────────────
# Input:  $1 = prompt string, $2 = count (fallback pra mock), $3 = field
# Output: JSON array em stdout
# Exit:   0 sucesso, 1 falha (caller decide fallback)
#
# Modos:
#   MOCK     → array de strings "field var 1", "field var 2", ...
#   API SDK  → lib/_py/claude_invoke_api.py
#   ORCHEST  → signal file, orchestrator responde via Task tool
claude_invoke() {
  local prompt="$1"
  local count="${2:-4}"
  local field="${3:-var}"

  # Modo 1: MOCK
  if [[ "${META_ADS_COPY_MOCK:-0}" == "1" ]]; then
    python3 - "$count" "$field" <<'PYEOF'
import json, sys
count, field = int(sys.argv[1]), sys.argv[2]
print(json.dumps([f"{field} var {i}" for i in range(1, count + 1)]))
PYEOF
    return 0
  fi

  # Modo 2: API SDK direto (CI/fallback)
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    python3 "${_COPY_GEN_PY_DIR}/claude_invoke_api.py" "$prompt"
    return $?
  fi

  # Modo 3: signal file pro orchestrator
  local tmpdir signal_file prompt_file output_file
  tmpdir=$(mktemp -d -t metacopy.XXXXXX)
  signal_file="${tmpdir}/signal"
  prompt_file="${tmpdir}/prompt.txt"
  output_file="${tmpdir}/output.json"
  # shellcheck disable=SC2064
  trap "rm -rf \"$tmpdir\"" RETURN

  printf '%s' "$prompt" > "$prompt_file"
  {
    echo "CLAUDE_CODE_INVOKE_SUBAGENT"
    echo "prompt_file=$prompt_file"
    echo "output_file=$output_file"
    echo "expected_format=json_array"
    echo "count=$count"
  } > "$signal_file"

  # Timeout 60s pro orchestrator responder
  local timeout="${META_ADS_COPY_TIMEOUT:-60}"
  local deadline=$(( $(date +%s) + timeout ))
  while [[ ! -s "$output_file" ]]; do
    if (( $(date +%s) >= deadline )); then
      echo "claude_invoke: timeout ${timeout}s aguardando orchestrator" >&2
      echo "[]"
      return 1
    fi
    sleep 1
  done

  cat "$output_file"
}
