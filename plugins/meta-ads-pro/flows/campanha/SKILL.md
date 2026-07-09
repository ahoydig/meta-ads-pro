---
name: meta-ads-campanha
description: CRUD de campanhas Meta Ads — criar/listar/editar/pausar/ativar/deletar. Fix dos bugs #1 (is_adset_budget_sharing_enabled) e #10 (preflight). Suporta 6 objetivos (LEADS/SALES/TRAFFIC/ENGAGEMENT/AWARENESS/APP_PROMOTION), ABO/CBO, 5 bid strategies.
---

# meta-ads-campanha

CRUD de campanhas. Invocada pela orquestradora ou direto via `/meta-ads-campanha`.

## Modos

- **Criar** — fluxo interativo de 8 passos
- **Listar** — `/meta-ads-campanha list [filter]`
- **Editar** — `/meta-ads-campanha edit {id}`
- **Pausar/Ativar** — `/meta-ads-campanha pause|activate {id}`
- **Deletar** — `/meta-ads-campanha delete {id}` (só se PAUSED)

## Fluxo de criação (8 passos)

### Passo 1 — Pre-flight
Delega pra orquestradora (já passou doctor). Assume `CURRENT_RUN_ID` setado e `AD_ACCOUNT_ID` no env (de CLAUDE.md).

Se invocada direta (sem orquestradora), roda `lib/preflight.sh` em modo `--silent` antes de tudo.

### Passo 2 — Produto/serviço
Pergunta: "Qual o produto/serviço sendo anunciado?" (1 linha).
Salva em `CAMPAIGN_PRODUCT`.

### Passo 3 — Objetivo

| # | Objetivo | Meta value | Quando usar |
|---|----------|-----------|-------------|
| 1 | Leads | `OUTCOME_LEADS` | Cadastros, lead forms, WA pra qualificação |
| 2 | Vendas | `OUTCOME_SALES` | E-commerce, conversões de site |
| 3 | Tráfego | `OUTCOME_TRAFFIC` | Cliques pra site, brandawareness |
| 4 | Engajamento | `OUTCOME_ENGAGEMENT` | Conversations (WA/Messenger), post engagement |
| 5 | Reconhecimento | `OUTCOME_AWARENESS` | Reach, video views |
| 6 | Instalação app | `OUTCOME_APP_PROMOTION` | Mobile app installs |

### Passo 4 — Destino (influencia objetivo default)
Pergunta: Site / Lead Form / WhatsApp / Messenger / Call.
Salva em `CAMPAIGN_DESTINATION` (usado só pra nomenclatura aqui — o destino real é configurado no ad set).

### Passo 5 — Otimização (CBO vs ABO)
- **ABO (padrão):** orçamento por ad set. Campanha NÃO manda `daily_budget`.
- **CBO:** orçamento na campanha (Meta distribui). Campanha manda `daily_budget` em centavos.

### Passo 6 — Budget diário
- Se ABO: pula (budget é do ad set).
- Se CBO: pergunta valor em R$/dia. Valida `>= min_daily_budget` do CLAUDE.md (evita erro 1487534).

### Passo 7 — Bid strategy

| Strategy | Quando |
|----------|--------|
| `LOWEST_COST_WITHOUT_CAP` | Default — Meta otimiza pelo mínimo custo |
| `LOWEST_COST_WITH_BID_CAP` | Controle manual de lance máximo |
| `COST_CAP` | Limite de CPA (custo por aquisição) |
| `LOWEST_COST_WITH_MIN_ROAS` | Vendas com ROAS mínimo garantido |
| `TARGET_COST` | Custo-alvo (em deprecação pela Meta) |

### Passo 8 — Preview + confirmação

```
┌─ PREVIEW CAMPANHA ──────────────────────────────┐
│ Nome: {nome gerado via gen_name}                │
│ Objetivo: {obj}                                 │
│ Destino: {dest}                                 │
│ Otimização: {ABO/CBO}                           │
│ Budget: R$ {X}/dia                              │
│ Bid: {strategy}                                 │
│ Status: PAUSED                                  │
└─────────────────────────────────────────────────┘

Confirma criação? [s/n/p=preview visual]
```

Se `s` → POST para `${AD_ACCOUNT_ID}/campaigns`:

**Se CBO** (budget na campanha):

```json
{
  "name": "{nome}",
  "objective": "{objetivo}",
  "status": "PAUSED",
  "special_ad_categories": [],
  "is_adset_budget_sharing_enabled": false,
  "bid_strategy": "{strategy}",
  "daily_budget": {budget_cents}
}
```

**Se ABO** (budget no ad set, não na campanha) — payload SEM `bid_strategy` nem `daily_budget`:

```json
{
  "name": "{nome}",
  "objective": "{objetivo}",
  "status": "PAUSED",
  "special_ad_categories": [],
  "is_adset_budget_sharing_enabled": false
}
```

- `is_adset_budget_sharing_enabled: false` — **FIX BUG #1** (sempre enviado, mesmo ABO).
- `daily_budget` — **só se CBO**. Em ABO, omitir o campo (o budget fica no ad set).
- `bid_strategy` — **só se CBO, mesma regra do `daily_budget`** (achado ao vivo T22): a conta rejeita `bid_strategy` na campanha quando ela não tem `daily_budget` próprio — erro `100/1885737` "Esta campanha não tem orçamento. Adicione um orçamento para editar a estratégia de lance." Em ABO, `bid_strategy` vai no ad set (ver `/meta-ads-conjuntos`, Passo 11 — herda o valor escolhido aqui no Passo 7 via `CAMPAIGN_BID_STRATEGY`), nunca na campanha.

Após 200/201:
1. Lê `campaign_id` da resposta.
2. Registra no manifest: `manifest_add campaign $campaign_id`.
3. Exporta `LAST_CAMPAIGN_ID=$campaign_id` pra próximas sub-skills encadearem.
4. Emite evento: `telemetry_log campaign_created id=$campaign_id objective=$objective opt=$opt`.

### Passo 9 — Encadear pro conjunto (jornada fim-a-fim)

Campanha sozinha não veicula. Pergunta sempre:

```
✓ Campanha criada (PAUSED). ID: {campaign_id}

Continuar pra criar o conjunto de anúncios agora? [S/n] [S]:
```

- `S` (default) → invoca `/meta-ads-conjuntos` com `LAST_CAMPAIGN_ID` já no env. O conjunto, ao terminar, vai perguntar a mesma coisa pro anúncio.
- `n` → para aqui. Mostra: `Pra continuar depois: /meta-ads-conjuntos (vai usar a campanha {campaign_id} automaticamente).`

**Regra:** invocação direta de `/meta-ads-campanha` SEMPRE oferece encadeamento. Só pula se user passou flag `--no-chain`.

## Listar

```bash
graph_api GET "${AD_ACCOUNT_ID}/campaigns?fields=id,name,status,objective,daily_budget,bid_strategy&limit=50"
```

Filtros aceitos:
- `list active` — só status=ACTIVE
- `list paused` — só status=PAUSED
- `list all` — tudo

Renderiza tabela ASCII (id · name · status · objective · budget).

## Editar

`/meta-ads-campanha edit {id}` permite alterar:
- `name`
- `daily_budget` (só se CBO — valida `>= min_daily_budget`)
- `bid_strategy` (só se CBO — campanha ABO sem `daily_budget` rejeita `bid_strategy` isolado, mesmo erro `100/1885737` do Passo 8)

POST para `${id}` com o(s) campo(s) alterados.

## Pausar / Ativar

```bash
graph_api POST "{id}" '{"status":"PAUSED"}'
graph_api POST "{id}" '{"status":"ACTIVE"}'
```

## Deletar

**Regra dura:** só deleta se status == `PAUSED`. Se `ACTIVE`, bloqueia com mensagem:

```
✗ Não dá pra deletar campanha ACTIVE. Pausa antes:
  /meta-ads-campanha pause {id}
```

Fluxo:
1. `graph_api GET "{id}?fields=status"` — lê status atual.
2. Se `ACTIVE` → aborta com erro acima.
3. Se `PAUSED` → `graph_api DELETE "{id}"`.

## Regras

- Sempre `status: PAUSED` ao criar (usuário ativa depois, nunca cria ativa).
- Sempre `is_adset_budget_sharing_enabled: false` (ABO) — fix bug #1.
- Sempre `special_ad_categories: []` (evita warnings em conta sem categoria especial).
- `daily_budget` só em CBO; em ABO o campo NÃO vai no payload.
- `bid_strategy` só em CBO; em ABO o campo NÃO vai no payload da campanha (vive no ad set — ver `/meta-ads-conjuntos`). Achado ao vivo T22: `100/1885737`.
- DELETE bloqueado se status == ACTIVE.
- Pode deletar PAUSED diretamente (Meta API aceita).

## Erros específicos

Ver `lib/error-catalog.yaml`. Campanha:
- `100/4834011` — `is_adset_budget_sharing_enabled` ausente → resolver adiciona `false` (bug #1).
- `1487534` — daily_budget < min do account → aumenta pro mínimo da API.
- `1885183` — campanha em conta dev mode sem app live (fix via `FALLBACK_DARK_POST`).
- `613/80004` — rate limit → retry automático do `graph_api.sh`.
- `100/1885737` — `bid_strategy` setado na campanha sem `daily_budget` (campanha ABO) → remover `bid_strategy` do payload da campanha; ele deve ir no ad set (`/meta-ads-conjuntos`, achado ao vivo T22).
