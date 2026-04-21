# Changelog

Todas as mudanças notáveis do `meta-ads-pro`. Formato [Keep a Changelog](https://keepachangelog.com/),
versionamento [SemVer](https://semver.org/).

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
