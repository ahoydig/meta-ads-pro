#!/usr/bin/env bash
# tests/01-lint.sh — Camada 1: lint estático (shellcheck, yamllint, jq)
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

_pass() { echo "✓ $*"; (( PASS++ )) || true; }
_fail() { echo "✗ $*"; (( FAIL++ )) || true; }
_skip() { echo "⊘ $* (skip — ferramenta ausente)"; (( PASS++ )) || true; }

# ── shellcheck ────────────────────────────────────────────────────────────────
echo "→ shellcheck"
if ! command -v shellcheck &>/dev/null; then
  _skip "shellcheck não instalado"
else
  sh_files=()
  while IFS= read -r f; do
    sh_files+=("$f")
  done < <(find "$PLUGIN_ROOT/lib" -name "*.sh" -type f | sort)
  if (( ${#sh_files[@]} == 0 )); then
    _skip "shellcheck: nenhum .sh encontrado em lib/"
  else
    if shellcheck "${sh_files[@]}"; then
      _pass "shellcheck: ${#sh_files[@]} arquivo(s) OK"
    else
      _fail "shellcheck: erros encontrados"
    fi
  fi
fi

# ── yamllint (com key-duplicates) ─────────────────────────────────────────────
echo "→ yamllint"
if ! command -v yamllint &>/dev/null; then
  _skip "yamllint não instalado"
else
  YAML_TARGET="$PLUGIN_ROOT/lib/error-catalog.yaml"
  if [[ ! -f "$YAML_TARGET" ]]; then
    _fail "yamllint: $YAML_TARGET não encontrado"
  elif yamllint \
    -d '{extends: default, rules: {key-duplicates: enable, line-length: {max: 120}, document-start: disable}}' \
    "$YAML_TARGET" 2>&1; then
    _pass "yamllint: error-catalog.yaml válido (key-duplicates habilitado)"
  else
    _fail "yamllint: erro em error-catalog.yaml"
  fi
fi

# ── jq: plugin.json ───────────────────────────────────────────────────────────
echo "→ jq validate plugin.json"
if ! command -v jq &>/dev/null; then
  _skip "jq não instalado"
else
  JSON_TARGET="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  if [[ ! -f "$JSON_TARGET" ]]; then
    _fail "jq: $JSON_TARGET não encontrado"
  elif jq empty "$JSON_TARGET" 2>&1; then
    _pass "jq: plugin.json JSON válido"
  else
    _fail "jq: plugin.json inválido"
  fi
fi

# ── sumário ───────────────────────────────────────────────────────────────────
echo ""
echo "lint: $PASS passou, $FAIL falhou"
[[ "$FAIL" -eq 0 ]]
