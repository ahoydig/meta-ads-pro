```
███╗   ███╗███████╗████████╗ █████╗      █████╗ ██████╗ ███████╗    ██████╗ ██████╗  ██████╗
████╗ ████║██╔════╝╚══██╔══╝██╔══██╗    ██╔══██╗██╔══██╗██╔════╝    ██╔══██╗██╔══██╗██╔═══██╗
██╔████╔██║█████╗     ██║   ███████║    ███████║██║  ██║███████╗    ██████╔╝██████╔╝██║   ██║
██║╚██╔╝██║██╔══╝     ██║   ██╔══██║    ██╔══██║██║  ██║╚════██║    ██╔═══╝ ██╔══██╗██║   ██║
██║ ╚═╝ ██║███████╗   ██║   ██║  ██║    ██║  ██║██████╔╝███████║    ██║     ██║  ██║╚██████╔╝
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝    ╚═╝  ╚═╝╚═════╝ ╚══════╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝
                            plugin Claude Code · v1.0.3 · by @flavioahoy
```

**Gerenciamento completo de Meta Ads via Graph API v25.0 direto no Claude Code.**
Cinco destinos (Site, Lead Form, WhatsApp, Messenger, Call), criativos Normal e Dinâmico
(`asset_feed_spec`), lead forms com qualifier/disqualifier, rollback transacional, error
resolver com auto-learning e preview ASCII + HTML. Tudo portável bash 3.2+ (macOS / Linux).

---

## Quickstart

### Opção 1 — Via marketplace Claude Code (recomendado)

```bash
claude plugin marketplace add https://github.com/ahoydig/meta-ads-pro
claude plugin install meta-ads-pro@meta-ads-pro
```

Depois **sai do Claude Code e abre sessão nova** (os commands só aparecem no startup).

### Opção 2 — Via clone + install.sh

```bash
git clone https://github.com/ahoydig/meta-ads-pro.git
cd meta-ads-pro
./install.sh
```

O installer:

- Desinstala qualquer versão antiga da skill `meta-ads` (com backup timestamped)
- Copia o plugin pra `~/.claude/plugins/local/meta-ads-pro/`
- Registra em `installed_plugins.json` + habilita em `settings.json::enabledPlugins`
- Cria a árvore runtime em `~/.claude/meta-ads-pro/` (manifests, learnings, cache, reports)
- Detecta upgrade vs install novo e **preserva dados runtime**
- Checa dependências: `jq`, `python3 3.8+`, `curl`, `yq` (opcional), `sips` (macOS) ou
  `ImageMagick` (Linux)
- Avisa se as skills externas recomendadas (`humanizer`, `nomenclatura-utm`) não
  estiverem disponíveis

Depois de instalar (qualquer método):

```
/meta-ads-menu       # porta de entrada — banner + menu dos 13 comandos
/meta-ads-setup      # configuração inicial (11 passos)
/meta-ads-doctor     # diagnóstico do ambiente
```

---

## Commands

14 slash commands cobrem todo o ciclo:

| Command | O que faz |
|---------|-----------|
| `/meta-ads-menu` | Menu central — banner + lista dos comandos agrupados + jornadas típicas |
| `/meta-ads-setup` | Setup inicial: valida token, descobre recursos, grava `.env` + `CLAUDE.md` |
| `/meta-ads-doctor` | 10 checks de ambiente + 6 flags (`--fix`, `--silent`, `--report`, `--release-lock`, `--review-learnings`) |
| `/meta-ads-campanha` | CRUD de campanhas (criar em 8 passos, list/edit/pause/activate/delete) |
| `/meta-ads-conjuntos` | CRUD de ad sets com 5 destinos + geocoding ViaCEP/Nominatim |
| `/meta-ads-anuncios` | Criar anúncios Normal ou Dinâmico com upload multipart + copy humanizada |
| `/meta-ads-lead-forms` | Instant Forms: criar/listar/editar/deletar/export + qualifier/disqualifier |
| `/meta-ads-publicos` | Custom audiences + Lookalikes + Website/Pixel audiences |
| `/meta-ads-regras` | Automated rules (6 templates + construtor custom) |
| `/meta-ads-insights` | Relatórios de performance em qualquer nível + breakdowns + async reports |
| `/meta-ads-import-existing` | Importa estrutura pré-plugin (GET-only, zero escrita) |
| `/meta-ads-rollback {run_id}` | Rollback manual topológico de um run específico |
| `/meta-ads-update` | `git fetch && pull --ff-only && ./install.sh` + mostra CHANGELOG |
| `/meta-ads-analyze-telemetry` | Relatório local de uso (top erros, taxa sucesso, duração) |

---

## Configuração

### `.env` (gerado pelo `/meta-ads-setup`)

```bash
META_ACCESS_TOKEN=EAA...            # System User token com ads_management + ads_read + pages_read_engagement + leads_retrieval
META_APP_ID=123...
META_APP_SECRET=abc...
```

Nunca commitar. O plugin nunca ecoa `$META_ACCESS_TOKEN` em stdout/stderr.

### `CLAUDE.md` (seção `## Meta Ads Config`)

```markdown
## Meta Ads Config
ad_account_id: act_763408067802379
page_id: 108356564252733
pixel_id: 947064561562400
instagram_user_id: 17841436814014233
currency: BRL
timezone: America/Recife
min_daily_budget: 518

## Nomenclatura Config
prefixo: ahoy
template_campaign: "{prefixo}_{objetivo}_{data}_{nome-criativo}"
template_adset:    "{prefixo}_{destino}_{publico}_{data}"
template_ad:       "{prefixo}_{formato}_{variacao}_{data}"
```

A nomenclatura é 100% customizável — 3 estilos prontos ou template livre com
placeholders (`{prefixo}`, `{objetivo}`, `{destino}`, `{data}`, `{nome-criativo}`,
etc). Fix do bug #6 do caso Filipe.

### Feature flags

Em `~/.claude/meta-ads-pro/feature-flags.yaml`:

```yaml
dry_run: false
ask_before_activate: true
humanizer_required: false
```

Ou via env: `META_ADS_DRY_RUN=1`, `META_ADS_NO_TELEMETRY=1`, `META_ADS_COPY_MOCK=1`.

---

## Exemplos — 5 destinos de campanha

### 1. Site externo (tráfego pro link)

```
/meta-ads-campanha
> Objetivo: OUTCOME_TRAFFIC
> Budget: R$ 30/dia (ABO)

/meta-ads-conjuntos
> Destino: Site externo
> URL: https://ahoy.digital/workshop
> Pixel event: Lead
> Público: Lookalike 1% BR | Idade 25-45 | Interesses: Marketing Digital
> Geo: Brasil (país inteiro)

/meta-ads-anuncios
> Formato: Dinâmico (asset_feed_spec)
> 5 images + 3 headlines + 3 primary_text + 2 descriptions → 1 ad com asset_feed_spec
```

### 2. Lead Form (Instant Form nativo)

```
/meta-ads-lead-forms
> Nome: Workshop IA Prática — Formulário
> Privacy URL: https://ahoy.digital/privacidade
> Campos: nome, email, telefone, empresa
> Qualifier: "Você já investe em tráfego pago hoje?" → Sim/Não
> Disqualifier: Se "Não" → thank_you desqualificado
> Thank you qualificado: "Obrigado! Te chamamos em 24h"
> Thank you desqualificado: "Obrigado pelo interesse. Temos conteúdo gratuito em @flavioahoy"

/meta-ads-campanha  → objetivo OUTCOME_LEADS
/meta-ads-conjuntos → destino Lead Form → seleciona o form acima
/meta-ads-anuncios  → CTA "Saiba mais"
```

### 3. WhatsApp (click-to-WhatsApp)

```
/meta-ads-campanha
> Objetivo: OUTCOME_ENGAGEMENT (click-to-message)

/meta-ads-conjuntos
> Destino: WhatsApp
> Número: +55 81 99999-0000 (validado contra a Page)
> Mensagem pré-preenchida: "Oi! Vi o anúncio do workshop e queria mais info."

/meta-ads-anuncios
> CTA: Enviar mensagem
```

### 4. Messenger

```
/meta-ads-conjuntos
> Destino: Messenger
> Welcome message: "Oi! Bem-vindo, posso te ajudar em quê?"
> Quick replies: ["Quero info", "Quero preço", "Quero falar com humano"]
```

### 5. Chamada (Phone Call)

```
/meta-ads-conjuntos
> Destino: Chamada
> Telefone: +55 81 3333-0000
> Horário: Seg-Sex 09-18h (dayparting)
```

---

## Troubleshooting

**Primeira parada é sempre o doctor:**

```bash
/meta-ads-doctor              # 10 checks
/meta-ads-doctor --fix        # tenta fix automático (ex: migrar legacy config)
/meta-ads-doctor --report     # snapshot JSON em ~/.claude/meta-ads-pro/reports/
/meta-ads-doctor --release-lock       # remove lockfile órfão após crash
/meta-ads-doctor --review-learnings   # revisa padrões de erro aprendidos
```

Os 10 checks cobrem: token válido, scopes corretos, app mode (Live vs Dev),
rate limit, ad account acessível, page token, pixel disponível, `CLAUDE.md`
presente, learnings consistentes, sips/ImageMagick disponível.

Se o doctor falhar, a mensagem inclui o fix exato (comando pra rodar, link
pra Graph API Explorer, ou passo manual).

**Outros comandos de recovery:**

- `/meta-ads-rollback {run_id}` — desfaz um run manual ou failed
- `/meta-ads-analyze-telemetry --days 30` — investiga erros recorrentes
- `./uninstall.sh` — remove o plugin (dados runtime preservados por padrão)

**Rate limit Meta:** o header `X-Business-Use-Case-Usage` tem
`estimated_time_to_regain_access` (minutos). Qualquer uma das 3 métricas
(call_count, cpu_time, total_time) chegando a 100% bloqueia por ~1h. O
plugin lê o header e mostra o tempo exato — nunca chuta.

---

## Contribuindo

- **Commits granulares**: um escopo por commit (`feat(lib)`, `test(regression)`, `fix(resolver)`, `docs`, etc).
- **shellcheck zero warnings**: `shellcheck lib/*.sh commands/*.sh tests/*.sh` antes de abrir PR.
- **bash 3.2 portável**: sem `mapfile`, sem `declare -A` com inline values, sem sintaxe GNU-only em `sed`/`grep`. Testar em `/bin/bash --version` (macOS default = 3.2.57).
- **Testes primeiro**: bug regression test em `tests/00-regression-filipe.sh` antes do fix.
- **Conventions**: pt-BR nos comentários e mensagens, terminologia técnica em EN (bash/API/etc), `$CLAUDE_PLUGIN_ROOT` pra paths relativos, Python via `lib/_py/` pra lógica não-shell.

Suite de testes local:

```bash
bash tests/run_all.sh            # todas as camadas
bash tests/run_all.sh --smoke    # inclui smoke live (precisa token)
bash tests/01-lint.sh            # shellcheck
bash tests/02-components.sh      # unit das libs
bash tests/00-regression-filipe.sh   # regression dos 10 bugs
```

---

## License

MIT — veja [LICENSE](./LICENSE).

Copyright © 2026 Flávio Rafael Montenegro.
