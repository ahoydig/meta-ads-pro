---
name: meta-ads-orquestradora
description: Porta de entrada do plugin meta-ads-pro. Renderiza banner, dispara pre-flight doctor, roteia intenção do usuário pra sub-skill correta, executa fluxo completo com rollback transacional + telemetria.
---

# meta-ads (orquestradora)

Ponto de entrada do plugin. Roteia intenções pra sub-skills específicas e coordena fluxo completo quando o pedido cobre múltiplas etapas.

## Pré-requisitos

1. Plugin instalado via `install.sh`
2. `.env` no projeto com `META_ACCESS_TOKEN`
3. `CLAUDE.md` do projeto com seção `## Meta Ads Config`
4. Skill `humanizer` recomendada (não obrigatória — fallback disponível)

## Fluxo de execução

### Passo 1 — Banner de boas-vindas (primeira vez)

```bash
if [[ ! -f .meta-ads-initialized ]]; then
  bash $CLAUDE_PLUGIN_ROOT/lib/banner.sh
  echo ""
  echo "⚙ Primeira vez nesse projeto. Vou disparar /meta-ads-setup..."
  # dispara setup automático
fi
```

### Passo 2 — Pre-flight silent

```bash
source $CLAUDE_PLUGIN_ROOT/lib/preflight.sh

# Checks críticos (bloqueiam se falhar)
check_token_valid || exit 2
check_rate_limit_buc || exit 2
check_ad_account_active || exit 2
check_claude_md_config || exit 2

# Checks warn (não bloqueiam)
check_scopes || true
check_app_mode
check_page_token || true
check_pixel || true
```

Se doctor passou, exporta flags:
- `FALLBACK_DARK_POST` (bool) — usado por anuncios
- `AD_ACCOUNT_ID`, `PAGE_ID`, `INSTAGRAM_USER_ID` — das envs do CLAUDE.md

### Passo 3 — Acquire lockfile

```bash
source $CLAUDE_PLUGIN_ROOT/lib/lockfile.sh
RUN_ID="meta-ads-$(date +%Y%m%d-%H%M%S)-$RANDOM"
acquire_lock "$AD_ACCOUNT_ID" "$RUN_ID" || exit 3
setup_lock_cleanup "$AD_ACCOUNT_ID"
export CURRENT_RUN_ID="$RUN_ID"
```

### Passo 4 — Init manifest

```bash
source $CLAUDE_PLUGIN_ROOT/lib/rollback.sh
manifest_init "$RUN_ID" "$AD_ACCOUNT_ID"
```

### Passo 5 — Telemetria de início

```bash
source $CLAUDE_PLUGIN_ROOT/lib/telemetry.sh
telemetry_log run_started run_id="$RUN_ID" sub_skill="$SUB_SKILL"
```

### Passo 6 — Interpreta intenção do usuário

Tabela de roteamento:

| Intenção do usuário | Sub-skill |
|--------------------|-----------|
| "subir campanha", "lançar anúncio", "criar campanha completa" | Fluxo completo (campanha → conjuntos → anuncios [→ lead-forms]) |
| "criar conjunto", "ad set", "targeting", "segmentação" | `conjuntos/` |
| "criar anúncio", "subir criativo", "upload video/imagem" | `anuncios/` |
| "criar público", "lookalike", "audiência", "remarketing" | `publicos/` |
| "criar regra", "otimizar automático", "automação", "escalar" | `regras/` |
| "performance", "relatório", "insights", "métricas", "CPA", "ROAS" | `insights/` |
| "listar campanhas", "ver campanhas ativas" | `campanha/` (modo listagem) |
| "pausar", "ativar", "editar campanha X" | `campanha/` (modo edição) |
| "criar form", "lead form", "formulário" | `lead-forms/` |
| "diagnosticar", "doctor", "o que tá errado" | `doctor/` |
| "configurar", "setup", "trocar conta" | `setup/` |
| "importar", "importar dados existentes" | `import-existing/` |
| "rollback", "deletar run X" | `rollback` |

**Em ambiguidade:** pergunta ao usuário antes de delegar.

### Passo 7 — Fluxo completo (quando é "subir campanha completa")

Sequência orquestrada:

```
1. /meta-ads-campanha   → cria campanha PAUSED, registra em manifest
   ↓
2. [se destino=LEAD_FORM] /meta-ads-lead-forms → cria form, retorna form_id
   ↓
3. /meta-ads-conjuntos  → cria ad set PAUSED (passa form_id se aplicável)
   ↓
4. /meta-ads-anuncios   → cria N ads PAUSED (Normal ou Dinâmico)
   ↓
5. Resumo final → IDs + links Ads Manager + preview URL
   ↓
6. Pergunta "ativar agora?" → se sim, muda status pra ACTIVE em cascata
```

Em qualquer falha dos passos 1-4, invoca `rollback_run $RUN_ID`.

### Passo 8 — Telemetria de fim

```bash
telemetry_log run_completed run_id="$RUN_ID" duration_ms=$((($(date +%s) - START_TS) * 1000)) objects_created=$OBJ_COUNT
release_lock "$AD_ACCOUNT_ID"
```

### Passo 9 — Review de learnings (opcional, 1x/semana)

Se `~/.claude/meta-ads-pro/learnings/unknown_errors.jsonl` tem entries novos desde última revisão:

```
> "Ei, tenho 3 learnings novos de erros desde a última revisão. Quer:
>   [1] Abrir pra revisar agora
>   [2] Enviar como issue no github.com/ahoydig/meta-ads-pro
>   [3] Deixar pra depois"
```

Se [1] ou [2], chama `/meta-ads-doctor --review-learnings`.

## Regras invioláveis

1. **Sempre PAUSED na criação** — jamais criar objeto com status=ACTIVE sem confirmação explícita
2. **Sempre preview antes de POST** — invoca `lib/visual-preview.sh` (ASCII ou HTML)
3. **Sempre confirmar ativação** — ao final do fluxo, pergunta antes de mudar pra ACTIVE
4. **Rollback automático em falha** — em qualquer erro não resolvido pelo error-resolver, roda `rollback_run`
5. **Nunca ecoar token** — `$META_ACCESS_TOKEN` nunca aparece em output ao usuário
6. **Respeita lockfile** — segunda invocação na mesma conta bloqueia

## Sub-skills disponíveis

| Skill | Command | Responsabilidade |
|-------|---------|-----------------|
| Setup | `/meta-ads-setup` | Configuração inicial (token, descoberta, nomenclatura) |
| Doctor | `/meta-ads-doctor` | Diagnóstico + fix automático + review learnings |
| Campanha | `/meta-ads-campanha` | CRUD de campanhas |
| Conjuntos | `/meta-ads-conjuntos` | Ad sets com 5 destinos |
| Anúncios | `/meta-ads-anuncios` | Creatives Normal/Dinâmico + upload + geração copy |
| Lead Forms | `/meta-ads-lead-forms` | Instant Forms CRUD |
| Públicos | `/meta-ads-publicos` | Custom audiences + lookalikes |
| Regras | `/meta-ads-regras` | Automated rules |
| Insights | `/meta-ads-insights` | Relatórios de performance |
| Import | `/meta-ads-import-existing` | Importa dados pré-plugin |
| Rollback | `/meta-ads-rollback {run_id}` | Rollback manual |
| Update | `/meta-ads-update` | git pull + ./install.sh |
| Telemetry | `/meta-ads-analyze-telemetry` | Agrega eventos locais |

## Erros comuns — referência global

Ver `lib/error-catalog.yaml` pra lista completa de 25 erros mapeados com fixes automáticos.
