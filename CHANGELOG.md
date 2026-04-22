# Changelog

Todas as mudanças notáveis do `meta-ads-pro`. Formato [Keep a Changelog](https://keepachangelog.com/),
versionamento [SemVer](https://semver.org/).

---

## [v1.0.6] — 2026-04-21

Hotfix — detecção cross-plugin robusta.

### Fixed

- **`/meta-ads-dna` detection quebrada em cache-only** — o glob do
  `~/.claude/plugins/cache/*/dna-operacional/.claude-plugin/plugin.json`
  não batia no layout real `<marketplace>/<plugin>/<version>/.claude-plugin/`.
  Passava por acaso via o fallback `marketplaces/`. Fix: cascata de 3
  globs pra funcionar em qualquer configuração.

---

## [v1.0.5] — 2026-04-21

Feature aditiva — ponte com o plugin `dna-operacional`.

### Added

- **`/meta-ads-dna`** — ponte pro plugin `dna-operacional`. Faz detecção em
  dois níveis:
  1. Plugin instalado? (`~/.claude/plugins/cache/*/dna-operacional/`)
  2. DNA configurado no projeto atual? (`reference/publico-alvo.md` +
     `reference/voz-*.md`)
  Quatro estados possíveis — plugin ausente, plugin instalado mas projeto
  não configurado, setup parcial, tudo certo — cada um com instruções
  específicas. Se tudo certo, mostra mapa de integrações (roteiro-viral →
  ad copy, raio-x-ads-concorrentes → briefing, carrossel-instagram →
  asset_feed_spec, insights ↔ analista-conteudo).
- Seção 🔗 INTEGRAÇÕES no `/meta-ads-menu`.

### Notes

- Change puramente aditivo. Não toca em nenhum fluxo existente.
- Bridge bidirecional: dna-operacional v0.1.1+ expõe `/dna-meta-ads` que
  faz a detecção inversa.

---

## [v1.0.4] — 2026-04-21

Hotfix release — elimina namespace forçado no slash command.

### Fixed

- **`/meta-ads-menu` dava "Unknown command"** — Claude Code força namespace
  quando o `name` do marketplace é igual ao `name` do plugin. Com marketplace
  e plugin ambos `meta-ads-pro`, o único command invocável era
  `/meta-ads-pro:meta-ads-menu`, e o curto `/meta-ads-menu` falhava.
  Fix: renomeado marketplace para `meta-ads-pro-marketplace`. Plugin continua
  `meta-ads-pro`. Agora `/meta-ads-menu` funciona direto sem namespace.
- **Auto-execução de comando dentro do banner** — o hint do final do menu
  dizia `Digite: /meta-ads-menu jornadas` em texto puro. Claude Code (ou
  hooks de sessão) interpretava o `/...` no output como comando a executar,
  disparando "Unknown command" logo após o banner renderizar. Fix: hints
  agora vêm em backticks (`` `/meta-ads-menu jornadas` ``) pra sinalizar
  que são literais.
- **Version hardcoded v1.0.2 no menu** — atualizado pra v1.0.4.

### Breaking (migration path)

Install command mudou:

```bash
# Antes (v1.0.3):
claude plugin install meta-ads-pro@meta-ads-pro

# Agora (v1.0.4+):
claude plugin install meta-ads-pro@meta-ads-pro-marketplace
```

Pra migrar:

```bash
claude plugin uninstall meta-ads-pro@meta-ads-pro
claude plugin marketplace remove meta-ads-pro
claude plugin marketplace add https://github.com/ahoydig/meta-ads-pro
claude plugin install meta-ads-pro@meta-ads-pro-marketplace
```

---

## [v1.0.3] — 2026-04-21

Hotfix release — elimina duplicatas no autocomplete do Claude Code.

### Fixed

- **Skills fantasma no autocomplete** — o Claude Code expõe qualquer
  `SKILL.md` com `name:` no frontmatter como slash command. Como cada
  skill tinha `name: meta-ads-<algo>` e cada command também, o autocomplete
  mostrava duplicatas (`/meta-ads-setup` vinha tanto do `commands/` quanto
  da `skills/`), além de commands fantasma (`/meta-ads-orquestradora` —
  skill sem command correspondente) e duplicatas namespaceadas
  (`/meta-ads-pro:meta-ads-*`). Fix: pasta `skills/` renomeada pra `flows/`
  (não é convenção reservada). Conteúdo preservado, commands atualizados
  pra ler `flows/<nome>/SKILL.md`. Zero skills fantasma. Autocomplete
  volta a mostrar só os 14 slash commands reais.

### Upgrade

```bash
claude plugin marketplace update meta-ads-pro
claude plugin uninstall meta-ads-pro@meta-ads-pro
claude plugin install meta-ads-pro@meta-ads-pro
```

---

## [v1.0.2] — 2026-04-21

Distribution release — repo convertido em marketplace Claude Code + comando de
menu visual `/meta-ads-menu`. Fix do problema "plugin instalado não aparece no
autocomplete" ao usar `~/.claude/plugins/local/` sem `.claude-plugin/marketplace.json`.

### Added

- **`.claude-plugin/marketplace.json`** na raiz do repo — transforma o projeto
  em marketplace próprio. Instalação via CLI passa a ser suportada:
  ```
  claude plugin marketplace add https://github.com/ahoydig/meta-ads-pro
  claude plugin install meta-ads-pro@meta-ads-pro
  ```
- **`/meta-ads-menu`** — porta de entrada visual (banner ASCII + menu dos 13
  comandos agrupados + jornadas típicas). Padrão `/dna` do dna-operacional: só
  imprime texto, não invoca sub-skills, não pergunta. Argumentos: vazio
  (menu), `jornadas` (4 fluxos), `setup`/`doctor` (aponta pro command),
  fallback (menu com aviso).

### Changed

- **Repo layout** pra padrão marketplace: código do plugin vive em
  `plugins/meta-ads-pro/`. `install.sh` detecta e usa `SOURCE_DIR` correto
  automaticamente (compat com clones antigos).
- **`install.sh`** agora registra o plugin em `~/.claude/plugins/installed_plugins.json`
  e habilita em `~/.claude/settings.json::enabledPlugins` (sem isso, plugins em
  `local/` não carregavam commands).
- **URLs no plugin.json, README, skills**: `flavioahoy/meta-ads-pro` →
  `ahoydig/meta-ads-pro` (GitHub login real do autor).

### Fixed

- **Plugin cache stale** — Claude Code mantém cópia congelada em
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. `marketplace update`
  não invalida esse cache. Fix: bump de versão força re-download. Documentado
  no README (seção "Troubleshooting instalação").
- **Autocomplete confuso** — `/meta-ads` (sem sufixo) ficava por último na
  ordenação ASCII (hífen < ponto) e era ambíguo com os `/meta-ads-*`. Rename
  pra `/meta-ads-menu` explicita o propósito e entra no meio da lista.

---

## [v1.0.1] — 2026-04-21

Hotfix release — 7 bugs descobertos no smoke live REAL v1.0.0 em produção.
Apply-retry do bug #1 VALIDADO em produção (erro 100/4834011 → fix auto → campanha criada).

### Fixed

- **preflight standalone `BASH_SOURCE[0]` unset em bash 3.2** — fallback `${BASH_SOURCE[0]:-$0}`
  pra cobrir shell interativo com `set -u`. Commit `f57afee`.
- **`local status` colide com bash readonly var** — rename `acct_status` em `check_ad_account_active`.
  Commit `f57afee`.
- **`thank_you_page[button_type]` required pela Meta Graph API** — smoke-live adiciona
  `VIEW_WEBSITE + button_text + website_url` em thank you qualified + disqualified.
  Commit `5f95759`.
- **`context_card[style]` required** — smoke-live adiciona `LIST_STYLE + button_text`.
  Commit `faa45f1`.
- **Lead forms não suportam DELETE direto via API** — `rollback_run` detecta type=leadgen_form
  e usa `POST status=ARCHIVED` via page access token. Commit `b698996`.
- **Form name colide com ARCHIVED anteriores** — smoke-live gera `_SMOKE_form_YYYYMMDD_HHMMSS`.
  Commit `57e2ec7`.
- **Rollback com manifest vazio** — guard no início de `rollback_run` + skip linhas vazias
  na iteração. Commit `57e2ec7`.

### Validated in production

- Apply-retry loop (bug #1) executado end-to-end contra Meta real. Erro 100/4834011
  detectado, fix `add_field:is_adset_budget_sharing_enabled:false` aplicado, re-POST
  com sucesso. Campanha `120249218303640196` criada.
- Rollback topológico ad set → campaign → (form archived) funcional.
- Budget control inviolável: R$ 0,00 gasto em ~3min ativo (sem ad criado).

---

## [v1.0.0] — 2026-04-21

Release inicial pública. Plugin Claude Code completo pra gerenciamento de Meta Ads
via Graph API v25.0, com fix dos 10 bugs identificados no caso Filipe e suite de
testes de regressão permanente.

### Added

- **11 skills** (1 orquestradora + 10 sub-skills: `setup`, `doctor`, `campanha`,
  `conjuntos`, `anuncios`, `lead-forms`, `publicos`, `regras`, `insights`,
  `import-existing`)
- **5 destinos de campanha**: Site externo (`WEBSITE`), Lead Form (`ON_AD`),
  WhatsApp (`WHATSAPP`), Messenger (`MESSENGER`), Chamada (`PHONE_CALL`)
- **Tipos de criativo Normal e Dinâmico** (`asset_feed_spec` com combinatória
  nativa da Meta, sem produto cartesiano client-side)
- **Copy por IA + humanizer bridge**: geração T/D/L/TD/TDL via `copy_generator.sh`
  com 3 modos de invocação (Claude Code signal file, Anthropic SDK, mock) e
  pipeline de humanização transparente
- **Preview visual**: modo ASCII no terminal + HTML on-demand
- **Error resolver com auto-learning**: catálogo YAML + WebSearch fallback, grava
  padrões novos em `~/.claude/meta-ads-pro/learnings/unknown_errors.jsonl`
- **Rollback transacional topológico**: manifest por run, delete em ordem
  (ads → creatives → images → adsets → campaigns → forms), idempotente em 404,
  retry automático em 613/80004
- **Lockfile anti-race** em `~/.claude/meta-ads-pro/.lock`, com `--release-lock`
  pra casos de crash
- **Telemetria local JSONL** com opt-out via `META_ADS_NO_TELEMETRY=1` — zero
  dados saem da máquina
- **Feature flags** em `~/.claude/meta-ads-pro/feature-flags.yaml` (e env vars
  `META_ADS_DRY_RUN`, `META_ADS_COPY_MOCK`, etc)
- **`/meta-ads-doctor`** com 10 checks (token, scopes, app mode, rate limit, ad
  account, page token, pixel, CLAUDE.md, learnings, image tool) e 6 flags
  (`--fix`, `--silent`, `--report`, `--release-lock`, `--review-learnings`, default)
- **`/meta-ads-lead-forms`** com qualifier/disqualifier/conditional logic +
  validação de privacy URL bilíngue PT+EN em 3 camadas + cache 24h
- **`/meta-ads-import-existing`** — GET-only (zero escrita), paginação
  cursor-based, token redacted, gera snapshot timestamped em
  `history/{account}/imported-YYYYMMDD-HHMMSS.json`
- **`/meta-ads-rollback {run_id}`** — rollback manual de qualquer run
  (current/failures/history) com preview antes de deletar
- **`/meta-ads-update`** — `git pull --ff-only` + reinstalador + mostra CHANGELOG
  da nova versão
- **`/meta-ads-analyze-telemetry`** — relatório local de top erros,
  sub-skills mais usadas, taxa de sucesso, duração média
- **146+ testes automatizados** em 17 arquivos (regression, lint, components,
  doctor, campanha, conjuntos, anúncios, lead-forms, públicos, regras,
  insights, import, dry-run, integração, e2e, stress, smoke-live) + suite
  de regression dos 10 bugs
- **Cross-platform**: bash 3.2+ portável (macOS default), sips no Darwin,
  ImageMagick no Linux/WSL, BSD/GNU sed compat

### Fixed — 10 bugs do caso Filipe

- **#1 (subcode 1870227 — `is_adset_budget_sharing_enabled`)**
  Campanha ABO precisa de `is_adset_budget_sharing_enabled: false` explícito no
  POST. Ausente mascarava como erro 100/1870227 genérico.
- **#2 (subcode 1885183 — `targeting_automation.advantage_audience`)**
  Ad set recusava POST sem `targeting.targeting_automation.advantage_audience: 0`.
  Agora é enviado em **todo** POST de adset.
- **#3 (error 100/1885183 — dev mode dark post)**
  App em dev mode bloqueia `object_story_spec`. Preflight detecta e roteia
  automaticamente pro fluxo de dark post via `/page_id/feed` — transparente
  pro usuário (fallback controlado por `FALLBACK_DARK_POST`).
- **#4 (produto cartesiano em Dinâmico)**
  Plano anterior criava N×M ads (5 imgs × 3 headlines = 15 ads). Agora é
  **1 ad com `asset_feed_spec`** — combinatória feita pela Meta.
- **#5 (media_fbid reusado entre posts)**
  Cache composto por `sha256(file) + post_id` previne reuso cruzado. `media_fbid`
  nunca viaja entre anúncios de posts diferentes.
- **#6 (nomenclatura hardcoded)**
  3 estilos prontos (AHOY, snake_case, PASCAL) + template livre com placeholders
  (`{prefixo}`, `{objetivo}`, `{destino}`, `{data}`, `{nome-criativo}`). Case do
  Filipe: `[FORMULARIO][X][AUTO]` caixa alta funciona nativamente.
- **#7 (privacy policy Instagram aceita — bug do client)**
  Validação bilíngue PT+EN em 3 camadas: HEAD check, fetch com User-Agent,
  keyword match (`privacidade`/`privacy`/`cookies`/`LGPD`). URLs do Instagram
  (profile/bio/post) rejeitadas — exige domínio do anunciante. Cache 24h.
- **#8 (lead form sem thank_you desqualificado)**
  `thank_you_page` E `disqualified_thank_you_page` obrigatórios client-side
  antes do POST `/leadgen_forms`. Previne API aceitar config incompleta que
  depois gera experiência ruim pro lead desqualificado.
- **#9 (sem rollback transacional)**
  Run cria manifest em `~/.claude/meta-ads-pro/current/{run_id}.json`. Em
  qualquer falha mid-run, rollback automático em ordem topológica. Run
  bem-sucedido move pra `history/`, falho pra `failures/`.
- **#10 (sem preflight doctor)**
  `/meta-ads-doctor --silent` roda como preflight de toda sub-skill antes
  de POSTs reais. Bloqueia execução se token/scope/app mode estiverem
  inconsistentes. 10 checks + sugestões de fix.

### Upgrade path

O `install.sh` detecta instalações anteriores (`~/.claude/skills/meta-ads/`,
symlinks legados `meta-ads-*`, ou versão antiga em `~/.claude/plugins/meta-ads-pro/`):

- **Faz backup** pra `~/.claude/.meta-ads-backup-{timestamp}/` (recuperável)
- **Remove código antigo** mas **preserva `~/.claude/meta-ads-pro/`** (manifests,
  learnings, cache, reports, feature-flags) — upgrade nunca destrói dados runtime
- **`.env` e `CLAUDE.md`** dos projetos do usuário nunca são tocados
- **`uninstall.sh`** pede confirmação separada pra remover dados runtime

---

## [v1.0.0-alpha.1] — 2026-04-21

### Added

- Scaffold inicial do plugin (estrutura `.claude-plugin/`, `commands/`,
  `skills/`, `lib/`, `lib/_py/`, `tests/`)

---

## [Unreleased]

_Nada pendente._
