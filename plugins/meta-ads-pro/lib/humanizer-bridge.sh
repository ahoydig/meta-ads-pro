#!/usr/bin/env bash
# humanizer-bridge.sh — ponte pra skill humanizer com fallback em falha
#
# 3 modos de fallback (todos devolvem texto raw, sempre 200):
#   1. META_ADS_SKIP_HUMANIZER=1 — bypass explícito (user ou CI)
#   2. skill humanizer não instalada em ~/.claude/skills/humanizer/SKILL.md
#   3. timeout/crash do invocador — registra em ~/.claude/meta-ads-pro/failures/
#
# Nunca bloqueia o pipeline: "raw é melhor do que vazio".

set -euo pipefail

HUMANIZER_SKILL_PATH="${HUMANIZER_SKILL_PATH:-${HOME}/.claude/skills/humanizer/SKILL.md}"
HUMANIZER_TIMEOUT="${HUMANIZER_TIMEOUT:-30}"
HUMANIZER_FAILURES_DIR="${HUMANIZER_FAILURES_DIR:-${HOME}/.claude/meta-ads-pro/failures}"

_log_failure() {
  local reason="$1" raw="$2"
  mkdir -p "$HUMANIZER_FAILURES_DIR"
  local timestamp log
  timestamp=$(date +%Y%m%d-%H%M%S)
  log="${HUMANIZER_FAILURES_DIR}/humanizer-${timestamp}-$$.log"
  {
    echo "reason: $reason"
    echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "raw_text_length: ${#raw}"
    echo "---"
    echo "$raw"
  } > "$log"
}

# humanize_text <raw_text> [voice_file] → stdout: humanized (ou raw em fallback)
humanize_text() {
  local raw_text="$1"
  local voice_file="${2:-}"

  # Modo 1: bypass explícito
  if [[ "${META_ADS_SKIP_HUMANIZER:-0}" == "1" ]]; then
    printf '%s' "$raw_text"
    return 0
  fi

  # Modo 2: skill não instalada
  if [[ ! -f "$HUMANIZER_SKILL_PATH" ]]; then
    _log_failure "skill_not_installed" "$raw_text"
    echo "⚠ humanizer skill não instalada em $HUMANIZER_SKILL_PATH, usando raw" >&2
    printf '%s' "$raw_text"
    return 0
  fi

  # Modo 3: invocação real via CLAUDE_CODE_INVOKE_HUMANIZER pattern
  # (a skill de anúncios traduz isso em Task tool do orchestrator).
  # Aqui exportamos contrato por arquivo: signal + input + output.
  local tmpdir output_file signal_file input_file
  tmpdir=$(mktemp -d -t metahumanizer.XXXXXX)
  signal_file="${tmpdir}/signal"
  input_file="${tmpdir}/input.txt"
  output_file="${tmpdir}/output.txt"
  # shellcheck disable=SC2064
  trap "rm -rf \"$tmpdir\"" RETURN

  printf '%s' "$raw_text" > "$input_file"
  {
    echo "CLAUDE_CODE_INVOKE_HUMANIZER"
    echo "voice_file=$voice_file"
    echo "input_file=$input_file"
    echo "output_file=$output_file"
  } > "$signal_file"

  # Orchestrator escuta signal_file, executa humanizer, escreve output_file.
  # Timeout defensivo: se o fluxo não preencher o output em N segundos, raw.
  local deadline=$(( $(date +%s) + HUMANIZER_TIMEOUT ))
  while [[ ! -s "$output_file" ]]; do
    if (( $(date +%s) >= deadline )); then
      _log_failure "timeout_${HUMANIZER_TIMEOUT}s" "$raw_text"
      echo "⚠ humanizer timeout (${HUMANIZER_TIMEOUT}s), usando raw" >&2
      printf '%s' "$raw_text"
      return 0
    fi
    sleep 1
  done

  # Valida: se output_file tem conteúdo vazio-after-strip, devolve raw
  local humanized
  humanized=$(cat "$output_file")
  if [[ -z "${humanized// /}" ]]; then
    _log_failure "empty_output" "$raw_text"
    printf '%s' "$raw_text"
    return 0
  fi

  printf '%s' "$humanized"
}

# humanize_array <json_array> [voice_file] → stdout: humanized JSON array
#
# Itera sobre cada string do array, roda humanize_text, monta novo array.
# Silent fallback pra raw em cada item que falhar.
humanize_array() {
  local json_array="$1"
  local voice_file="${2:-}"

  # Export variables pro subprocess access
  export HUMANIZER_SKILL_PATH HUMANIZER_TIMEOUT HUMANIZER_FAILURES_DIR
  export META_ADS_SKIP_HUMANIZER="${META_ADS_SKIP_HUMANIZER:-0}"

  local bridge_path
  bridge_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/humanizer-bridge.sh"

  python3 - "$json_array" "$voice_file" "$bridge_path" <<'PYEOF'
import json
import os
import subprocess
import sys

payload, voice_file, bridge_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    arr = json.loads(payload)
except json.JSONDecodeError:
    print(payload)
    sys.exit(0)

if not isinstance(arr, list):
    print(payload)
    sys.exit(0)

result = []
for item in arr:
    s = item if isinstance(item, str) else json.dumps(item, ensure_ascii=False)
    try:
        out = subprocess.run(
            [
                "bash", "-c",
                f'source "$1" && humanize_text "$2" "$3"',
                "--", bridge_path, s, voice_file,
            ],
            capture_output=True,
            text=True,
            timeout=int(os.environ.get("HUMANIZER_TIMEOUT", "30")) + 5,
        )
        humanized = out.stdout if out.returncode == 0 else s
    except Exception:  # noqa: BLE001
        humanized = s
    result.append(humanized if humanized else s)

print(json.dumps(result, ensure_ascii=False))
PYEOF
}
