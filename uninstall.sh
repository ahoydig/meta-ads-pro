#!/usr/bin/env bash
# uninstall.sh — meta-ads-pro
#
# Remove o plugin instalado em ~/.claude/plugins/meta-ads-pro/.
# Opcionalmente remove os dados runtime em ~/.claude/meta-ads-pro/.
# Nunca toca em .env ou CLAUDE.md de projetos.
#
# Uso:
#   ./uninstall.sh
#
# Compat: bash 3.2+ · Darwin + Linux.
set -euo pipefail

PLUGIN_DIR="${HOME}/.claude/plugins/meta-ads-pro"
DATA_DIR="${HOME}/.claude/meta-ads-pro"

echo "⚠  Isso vai remover meta-ads-pro de:"
echo "   $PLUGIN_DIR"
echo ""

if [[ ! -d "$PLUGIN_DIR" ]] && [[ ! -d "$DATA_DIR" ]]; then
  echo "• Nada a remover — plugin não parece instalado."
  exit 0
fi

# Confirmação primeiro — se abortar, não desperdiça a pergunta sobre wipe
read -rp "Confirma desinstalação? [s/N] " confirm
case "$confirm" in
  s|S|sim|SIM|y|Y|yes|YES) ;;
  *) echo "Abortado."; exit 0 ;;
esac

# Só pergunta sobre wipe depois do confirm
wipe="N"
if [[ -d "$DATA_DIR" ]]; then
  read -rp "Remover também dados runtime ($DATA_DIR)? [s/N] " wipe
fi

# Remove plugin
if [[ -d "$PLUGIN_DIR" ]]; then
  rm -rf "$PLUGIN_DIR"
  echo "✓ Plugin removido ($PLUGIN_DIR)"
else
  echo "• Plugin já não estava instalado"
fi

# Opcional: wipe runtime
case "$wipe" in
  s|S|sim|SIM|y|Y|yes|YES)
    if [[ -d "$DATA_DIR" ]]; then
      rm -rf "$DATA_DIR"
      echo "✓ Dados runtime removidos ($DATA_DIR)"
    fi
    ;;
  *)
    if [[ -d "$DATA_DIR" ]]; then
      echo "⚙ Dados preservados em $DATA_DIR"
      echo "  (pra apagar depois: rm -rf \"$DATA_DIR\")"
    fi
    ;;
esac

echo ""
echo "• .env e CLAUDE.md dos seus projetos não foram tocados."
echo "• Backups de instalações anteriores (se existirem) em ~/.claude/.meta-ads-backup-*/"
echo ""
echo "Até a próxima. 👋"
