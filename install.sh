#!/usr/bin/env bash
# install.sh — meta-ads-pro installer v1.0.0
#
# Instala o plugin em ~/.claude/plugins/local/meta-ads-pro/ + registra em
# ~/.claude/plugins/installed_plugins.json + habilita em ~/.claude/settings.json.
# Cria árvore runtime
# de dados runtime em ~/.claude/meta-ads-pro/. Detecta a skill antiga
# (~/.claude/skills/meta-ads/) e symlinks legados, faz backup e remove.
# Faz upgrade de versão anterior preservando dados runtime.
#
# Uso:
#   ./install.sh
#
# Compat: bash 3.2+ (macOS default) · Darwin + Linux.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Marketplace layout: código do plugin vive em plugins/meta-ads-pro/ no repo.
# Fallback pro layout antigo (plugin na raiz) pra compat com clones históricos.
if [[ -d "${SCRIPT_DIR}/plugins/meta-ads-pro" ]]; then
  SOURCE_DIR="${SCRIPT_DIR}/plugins/meta-ads-pro"
else
  SOURCE_DIR="${SCRIPT_DIR}"
fi
PLUGIN_DIR="${HOME}/.claude/plugins/local/meta-ads-pro"
DATA_DIR="${HOME}/.claude/meta-ads-pro"
SKILLS_DIR="${HOME}/.claude/skills"
OLD_SKILL_DIR="${SKILLS_DIR}/meta-ads"
BACKUP_DIR="${HOME}/.claude/.meta-ads-backup-$(date +%Y%m%d-%H%M%S)"

# --- warnings collector (printed at the end) ------------------------------
WARNINGS=""
add_warning() {
  WARNINGS="${WARNINGS}  - $1"$'\n'
}

# --- banner ---------------------------------------------------------------
cat <<'BANNER'
╔════════════════════════════════════════╗
║   META ADS PRO · Installer v1.0.3      ║
║        by @flavioahoy                  ║
╚════════════════════════════════════════╝
BANNER
echo ""

# --- sanity: plugin manifest existe --------------------------------------
if [[ ! -f "${SOURCE_DIR}/.claude-plugin/plugin.json" ]]; then
  echo "✗ ERRO: .claude-plugin/plugin.json não encontrado em ${SOURCE_DIR}"
  echo "  Rode ./install.sh a partir da raiz do repositório clonado."
  exit 1
fi

# --- 1. Desinstala skill antiga automaticamente (backup first) -----------
old_found=0
if [[ -d "$OLD_SKILL_DIR" ]]; then
  old_found=1
fi
# Detecta symlinks/arquivos legados ~/.claude/skills/meta-ads-*
if compgen -G "${SKILLS_DIR}/meta-ads-*" > /dev/null 2>&1; then
  old_found=1
fi
# ZIP residual de instalações antigas via "plugin marketplace"
if [[ -f "${SKILLS_DIR}/meta-ads.zip" ]]; then
  old_found=1
fi

if [[ "$old_found" -eq 1 ]]; then
  echo "⚙ Skill antiga detectada — fazendo backup em $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"

  if [[ -d "$OLD_SKILL_DIR" ]]; then
    mv "$OLD_SKILL_DIR" "$BACKUP_DIR/" 2>/dev/null || {
      add_warning "Falha ao mover $OLD_SKILL_DIR — remova manualmente"
    }
  fi

  # Move symlinks/arquivos legados meta-ads-*
  shopt -s nullglob
  for legacy in "${SKILLS_DIR}"/meta-ads-*; do
    [[ -e "$legacy" ]] || continue
    mv "$legacy" "$BACKUP_DIR/" 2>/dev/null || rm -f "$legacy" 2>/dev/null || true
  done
  shopt -u nullglob

  if [[ -f "${SKILLS_DIR}/meta-ads.zip" ]]; then
    mv "${SKILLS_DIR}/meta-ads.zip" "$BACKUP_DIR/" 2>/dev/null || \
      rm -f "${SKILLS_DIR}/meta-ads.zip" 2>/dev/null || true
  fi

  echo "✓ Skill antiga desinstalada (recuperável em $BACKUP_DIR)"
  echo ""
fi

# --- 2. Detecta upgrade vs install novo ----------------------------------
if [[ -d "$PLUGIN_DIR" ]]; then
  old_ver="unknown"
  if [[ -f "${PLUGIN_DIR}/.claude-plugin/plugin.json" ]] && command -v jq >/dev/null 2>&1; then
    old_ver="$(jq -r '.version // "unknown"' "${PLUGIN_DIR}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")"
  fi
  new_ver="unknown"
  if command -v jq >/dev/null 2>&1; then
    new_ver="$(jq -r '.version // "unknown"' "${SOURCE_DIR}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")"
  fi
  echo "⚙ Upgrade detectado: v${old_ver} → v${new_ver}"
  echo "  (dados runtime em $DATA_DIR serão preservados)"
  rm -rf "$PLUGIN_DIR"
fi

# --- 3. Copia código para ~/.claude/plugins/meta-ads-pro/ ----------------
echo "⚙ Instalando plugin em $PLUGIN_DIR ..."
mkdir -p "$(dirname "$PLUGIN_DIR")"
cp -R "$SOURCE_DIR" "$PLUGIN_DIR"

# Remove .git (o plugin instalado não precisa do histórico git)
rm -rf "${PLUGIN_DIR}/.git" 2>/dev/null || true
# Remove caches de teste/scratch que eventualmente estejam no source
rm -rf "${PLUGIN_DIR}/.DS_Store" "${PLUGIN_DIR}/tests/.tmp" 2>/dev/null || true

echo "✓ Código instalado"

# --- 3.5. Registrar em installed_plugins.json + habilitar ----------------
# Claude Code só carrega plugins que estejam em installed_plugins.json
# com namespace {plugin}@local e habilitados em settings.json::enabledPlugins.
INSTALLED_JSON="${HOME}/.claude/plugins/installed_plugins.json"
SETTINGS_JSON="${HOME}/.claude/settings.json"

if [[ -f "$INSTALLED_JSON" ]]; then
  python3 - "$INSTALLED_JSON" "$PLUGIN_DIR" <<'PYEOF'
import json, sys, pathlib
from datetime import datetime, timezone
f, install_path = sys.argv[1], sys.argv[2]
p = pathlib.Path(f)
d = json.loads(p.read_text())
now = datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
d.setdefault('plugins', {})['meta-ads-pro@local'] = [{
    'scope': 'user',
    'installPath': install_path,
    'version': '1.0.3',
    'installedAt': now,
    'lastUpdated': now
}]
p.write_text(json.dumps(d, indent=2))
print('  ✓ registrado em installed_plugins.json')
PYEOF
fi

if [[ -f "$SETTINGS_JSON" ]]; then
  python3 - "$SETTINGS_JSON" <<'PYEOF'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d.setdefault('enabledPlugins', {})['meta-ads-pro@local'] = True
p.write_text(json.dumps(d, indent=2))
print('  ✓ habilitado em settings.json::enabledPlugins')
PYEOF
fi

# --- 4. Cria estrutura runtime (preserva se já existe) -------------------
mkdir -p \
  "${DATA_DIR}/current" \
  "${DATA_DIR}/history" \
  "${DATA_DIR}/failures" \
  "${DATA_DIR}/learnings" \
  "${DATA_DIR}/cache/privacy" \
  "${DATA_DIR}/dry-runs" \
  "${DATA_DIR}/reports"
echo "✓ Estrutura runtime em $DATA_DIR"
echo ""

# --- 5. Verifica dependências -------------------------------------------
echo "⚙ Checando dependências..."

if command -v jq >/dev/null 2>&1; then
  echo "  ✓ jq $(jq --version 2>/dev/null || echo '')"
else
  add_warning "jq não encontrado — obrigatório. macOS: brew install jq · Linux: apt install jq"
fi

if command -v python3 >/dev/null 2>&1; then
  echo "  ✓ python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
  add_warning "python3 não encontrado — obrigatório. Instale Python 3.8+"
fi

if command -v curl >/dev/null 2>&1; then
  echo "  ✓ curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
else
  add_warning "curl não encontrado — obrigatório pra Graph API"
fi

if command -v yq >/dev/null 2>&1; then
  echo "  ✓ yq $(yq --version 2>/dev/null | awk '{print $NF}')"
else
  add_warning "yq opcional — recomendado. macOS: brew install yq · Linux: snap install yq"
fi

# --- 5b. Checagem imagem (sips/ImageMagick) por OS -----------------------
OS="$(uname -s)"
case "$OS" in
  Darwin)
    if command -v sips >/dev/null 2>&1; then
      echo "  ✓ sips disponível (macOS nativo)"
    else
      add_warning "sips não encontrado (deveria vir no macOS) — preview visual degradado"
    fi
    ;;
  Linux)
    if command -v convert >/dev/null 2>&1; then
      echo "  ✓ ImageMagick disponível ($(convert --version 2>/dev/null | head -1 | awk '{print $3}'))"
    else
      add_warning "ImageMagick não encontrado — apt install imagemagick (ou equiv.) pra preview visual"
    fi
    ;;
  *)
    add_warning "SO '$OS' não testado oficialmente — macOS e Linux são suportados"
    ;;
esac

echo ""

# --- 6. Skills externas recomendadas -------------------------------------
echo "⚙ Checando skills externas..."

humanizer_ok=0
if [[ -d "${SKILLS_DIR}/humanizer" ]]; then
  humanizer_ok=1
elif [[ -d "${HOME}/.claude/plugins/dna-operacional" ]]; then
  humanizer_ok=1
fi
if [[ "$humanizer_ok" -eq 1 ]]; then
  echo "  ✓ humanizer disponível"
else
  add_warning "humanizer não instalada (recomendada) — copy gerada por IA será menos humana"
fi

if [[ -d "${SKILLS_DIR}/nomenclatura-utm" ]]; then
  echo "  ✓ nomenclatura-utm disponível"
else
  echo "  • nomenclatura-utm opcional — não instalada"
fi

echo ""

# --- 7. Warnings (se houver) ---------------------------------------------
if [[ -n "$WARNINGS" ]]; then
  echo "⚠ Avisos:"
  printf '%s' "$WARNINGS"
  echo ""
fi

# --- 8. Sucesso + next steps ---------------------------------------------
cat <<'DONE'
╔════════════════════════════════════════╗
║  ✓ Instalação concluída                ║
╠════════════════════════════════════════╣
║  Próximos passos:                      ║
║    /meta-ads-setup    (config inicial) ║
║    /meta-ads-doctor   (preflight)      ║
║    /meta-ads          (orquestradora)  ║
║                                        ║
║  Docs: github.com/flavioahoy/          ║
║        meta-ads-pro                    ║
╚════════════════════════════════════════╝
DONE
