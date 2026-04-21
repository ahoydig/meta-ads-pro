#!/usr/bin/env bash
# tests/run_all.sh — master runner: camadas 0–2 sempre, camada 6 com --smoke
# set -e intencionalmente omitido: run_layer captura falhas individualmente
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SMOKE_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke) SMOKE_FLAG="1"; shift ;;
    *) shift ;;
  esac
done

REPORTS_DIR="$SCRIPT_DIR/reports/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPORTS_DIR"

PASS=0; FAIL=0; SKIP=0
FAILED_LAYERS=()

# ── helpers ──────────────────────────────────────────────────────────────────
run_layer() {
  local name="$1" script="$2"
  echo ""
  echo "━━━━━━━━━ $name ━━━━━━━━━"

  if [[ ! -f "$script" ]]; then
    echo "SKIP: $(basename "$script") não existe ainda"
    (( SKIP++ )) || true
    return 0
  fi

  local log="$REPORTS_DIR/$(basename "$script" .sh).log"

  if bash "$script" 2>&1 | tee "$log"; then
    echo "✓ $name"
    (( PASS++ )) || true
  else
    echo "✗ $name FAILED — ver $log"
    (( FAIL++ )) || true
    FAILED_LAYERS+=("$name")
    return 1
  fi
}

# ── camadas sempre executadas ─────────────────────────────────────────────────
run_layer "Camada 0: regressão Filipe"   "$SCRIPT_DIR/00-regression-filipe.sh" || exit 1
run_layer "Camada 1: lint"               "$SCRIPT_DIR/01-lint.sh"              || exit 1
run_layer "Camada 2: components"         "$SCRIPT_DIR/02-components.sh"        || exit 1
# Camadas 3–5 (scripts 04..16) adicionadas nos CPs correspondentes

# ── smoke live: só com --smoke ────────────────────────────────────────────────
if [[ "${SMOKE_FLAG}" == "1" ]]; then
  run_layer "Camada 6: smoke live" "$SCRIPT_DIR/17-smoke-live.sh" || exit 1
fi

# ── relatório final ───────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " RESULTADO FINAL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✓ Passou:   $PASS camada(s)"
echo " ✗ Falhou:   $FAIL camada(s)"
echo " ⊘ Ignorado: $SKIP camada(s)"
if (( ${#FAILED_LAYERS[@]} > 0 )); then
  echo ""
  echo " Falhas:"
  for l in "${FAILED_LAYERS[@]}"; do echo "   • $l"; done
fi
echo ""
echo " Logs: $REPORTS_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAIL" -eq 0 ]]
