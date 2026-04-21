---
name: meta-ads-insights
description: "Relatórios e análise de performance do Meta Ads. Use quando o usuário mencionar: performance, relatório, insights, métricas, como tá a campanha, quanto gastei, CPA, CPL, ROAS, CTR, CPM, resultados de anúncios, custo por lead, custo por venda, alcance, impressões, frequência, retorno sobre investimento, breakdown por idade, breakdown por placement, breakdown por device, relatório por período, dados de campanha, dados de conjunto, dados de anúncio, análise de mídia paga."
---

# /meta-ads insights — Relatórios de Performance

Consulta de performance em qualquer nível do Meta Ads: conta, campanha, conjunto de anúncios ou anúncio individual. Suporta breakdowns demográficos, por placement e device, períodos predefinidos e intervalos customizados, além de async reports para grandes volumes de dados.

---

## Pré-requisitos

Credenciais carregadas pela orquestradora `meta-ads/`. Variáveis disponíveis: `META_ACCESS_TOKEN`, `AD_ACCOUNT_ID` (com ou sem `act_`).

**Wrapper único:** todas chamadas passam por `lib/graph_api.sh::graph_api` (retry + `error-resolver` + injeção de token). **Nunca** chame `curl` direto.

---

## 1. Endpoints por Nível

| Nível | Endpoint (via `graph_api`) | Quando usar |
|-------|----------------------------|-------------|
| **Account** | `act_{id}/insights` | Visão geral da conta |
| **Campaign** | `{campaign_id}/insights` | Performance de uma campanha |
| **Ad Set** | `{adset_id}/insights` | Performance de um conjunto |
| **Ad** | `{ad_id}/insights` | Performance de um anúncio |

---

## 2. Fluxo Interativo

Execute as perguntas **uma por vez**, nesta sequência:

### Passo 1 — O que quer ver?

> "Quer ver a conta toda, uma campanha específica, um conjunto ou um anúncio?"

- **Conta toda** → `act_{id}/insights` com `level=campaign` para detalhamento
- **Campanha específica** → listar:
  ```bash
  graph_api GET "act_${AD_ACCOUNT_ID#act_}/campaigns?fields=name,status,objective,effective_status&filtering=[{\"field\":\"effective_status\",\"operator\":\"IN\",\"value\":[\"ACTIVE\",\"PAUSED\"]}]"
  ```
- **Conjunto** → listar ad sets, escolher
- **Anúncio** → listar anúncios, escolher

### Passo 2 — Período

| Opção | `date_preset` |
|-------|---------------|
| Hoje | `today` |
| Ontem | `yesterday` |
| Últimos 3 dias | `last_3d` |
| Últimos 7 dias | `last_7d` |
| Últimos 14 dias | `last_14d` |
| Últimos 28 dias | `last_28d` |
| Últimos 30 dias | `last_30d` |
| Este mês | `this_month` |
| Mês passado | `last_month` |
| Este trimestre | `this_quarter` |
| Trimestre passado | `last_quarter` |
| Customizado | usar `time_range` (Seção 5) |

### Passo 3 — Breakdowns (opcional)

| Categoria | Breakdowns | Quando é útil |
|-----------|-----------|---------------|
| Demográfico | `age`, `gender` | Quem converte melhor |
| Placement | `publisher_platform`, `platform_position` | FB vs IG vs Reels |
| Device | `impression_device` | Mobile vs desktop |
| Região | `country`, `region` | Performance geográfica |
| **Nenhum** (padrão) | — | Agregado simples |

> Combinar mais de 2 breakdowns → recomendar async report (Seção 8).

### Passo 4 — Executar

Montar chamada via `graph_api GET` com `fields` conforme objetivo (Seção 3).

### Passo 5 — Formatar resultado

Tabela legível conforme Seção 7.

### Passo 6 — Destacar + sugerir

- **Melhor performer** (menor CPA/CPL ou maior ROAS)
- **Pior performer**
- **Oportunidades:** bom CTR com pouco budget; frequência alta; ad sets abaixo do alvo

---

## 3. Métricas por Objetivo

Use a tabela para montar `fields` de acordo com o objetivo da campanha consultada.

### Leads (`OUTCOME_LEADS`)

| Métrica | Campo | Obs |
|---------|-------|-----|
| Impressões | `impressions` | |
| Alcance | `reach` | |
| Frequência | `frequency` | |
| Cliques | `clicks` | |
| CTR | `ctr` | |
| Leads | `actions` | filtrar `action_type=lead` |
| CPL | `cost_per_action_type` | filtrar `action_type=lead` |
| CPM | `cpm` | |
| Gasto | `spend` | |

**`fields`:** `impressions,reach,frequency,clicks,ctr,spend,actions,cost_per_action_type,cpm`

### Vendas (`OUTCOME_SALES`)

| Métrica | Campo | Obs |
|---------|-------|-----|
| Impressões | `impressions` | |
| Alcance | `reach` | |
| Gasto | `spend` | |
| Compras | `actions` | `action_type=purchase` |
| Receita | `action_values` | `action_type=purchase` |
| ROAS | `purchase_roas` | |
| Custo/compra | `cost_per_action_type` | `action_type=purchase` |
| CPM | `cpm` | |

**`fields`:** `impressions,reach,spend,actions,action_values,purchase_roas,cost_per_action_type,cpm`

### Tráfego (`OUTCOME_TRAFFIC`)

**`fields`:** `impressions,reach,clicks,ctr,cpc,cost_per_inline_link_click,landing_page_views,spend,cpm`

### Engajamento (`OUTCOME_ENGAGEMENT`)

**`fields`:** `impressions,reach,post_engagement,page_likes,spend,cost_per_inline_post_engagement,actions`

### Awareness (`OUTCOME_AWARENESS`)

**`fields`:** `impressions,reach,frequency,cpm,spend`

### Vídeo

**`fields`:** `impressions,reach,video_p25_watched_actions,video_p50_watched_actions,video_p75_watched_actions,video_p100_watched_actions,video_thruplay_watched_actions,cost_per_thruplay,spend`

---

## 4. Exemplos de chamada

### Visão geral da conta — últimos 7 dias (Leads)

```bash
source "$CLAUDE_PLUGIN_ROOT/lib/graph_api.sh"
graph_api GET "act_${AD_ACCOUNT_ID#act_}/insights?fields=impressions,reach,frequency,clicks,ctr,spend,actions,cost_per_action_type,cpm&date_preset=last_7d&level=campaign"
```

### Campanha específica — ontem (Vendas)

```bash
graph_api GET "${campaign_id}/insights?fields=impressions,reach,spend,actions,action_values,purchase_roas,cost_per_action_type,cpm&date_preset=yesterday"
```

### Breakdown demográfico

```bash
graph_api GET "${campaign_id}/insights?fields=impressions,spend,actions,cost_per_action_type,ctr&breakdowns=age,gender&date_preset=last_7d"
```

### Breakdown por placement

```bash
graph_api GET "${campaign_id}/insights?fields=impressions,reach,spend,actions,cost_per_action_type,cpm&breakdowns=publisher_platform,platform_position&date_preset=last_14d"
```

### Breakdown por device

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/insights?fields=impressions,clicks,ctr,spend,cpm&breakdowns=impression_device&date_preset=last_30d&level=campaign"
```

### Breakdown por região (country)

```bash
graph_api GET "${adset_id}/insights?fields=impressions,reach,spend,actions,cost_per_action_type&breakdowns=country&date_preset=last_30d"
```

---

## 5. Período Customizado

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/insights?fields=impressions,reach,spend,actions,cost_per_action_type,cpm&time_range={\"since\":\"2026-03-01\",\"until\":\"2026-03-19\"}&level=campaign"
```

> **Limite:** 37 meses retroativos. Erro `3018` fora disso (ver `lib/error-catalog.yaml`).

---

## 6. Filtragem

### Apenas campanhas ativas

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/insights?fields=impressions,reach,spend,actions,cost_per_action_type,cpm&date_preset=last_7d&level=campaign&filtering=[{\"field\":\"campaign.effective_status\",\"operator\":\"IN\",\"value\":[\"ACTIVE\"]}]"
```

### Ad sets com gasto acima de R$ 50

```
&filtering=[{"field":"spend","operator":"GREATER_THAN","value":50}]
```

### Combinar filtros

```
&filtering=[
  {"field":"campaign.effective_status","operator":"IN","value":["ACTIVE"]},
  {"field":"spend","operator":"GREATER_THAN","value":10}
]
```

---

## 7. Formatação de Saída

### Regras

- Monetário: **R$** com 2 decimais (ex: `R$ 15,22`)
- Percentual: 1 decimal + `%` (ex: `2,1%`)
- Milhar: separador `.` (ex: `12.450`)
- ROAS: 2 decimais + `x` (ex: `3,45x`)
- Nomes de campanha: truncar em 30 chars

### Exemplo — Leads (últimos 7 dias)

```
Performance — Últimos 7 dias
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Campanha                        | Gasto     | Alcance | Leads | CPL       | CTR    | CPM
{prefixo}_ebooks_cadastros_lp   | R$ 350,00 | 18.420  | 23    | R$ 15,22  | 2,1%   | R$ 19,00
{prefixo}_curso-auto_vendas_wpp | R$ 520,00 | 24.100  | 8     | R$ 65,00  | 1,3%   | R$ 21,58
{prefixo}_lancamento_cadastros  | R$ 180,00 | 9.800   | 14    | R$ 12,86  | 3,2%   | R$ 18,37
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total                           | R$ 1.050  | 52.320  | 45    | R$ 23,33  | —      | R$ 20,07

🏆 Melhor performer: {prefixo}_lancamento (CPL R$ 12,86 — 47% abaixo da média)
⚠️  Pior performer: {prefixo}_curso-auto (CPL R$ 65,00 — 4x acima dos outros)
💡 Oportunidade: {prefixo}_lancamento tem CTR 3,2% com menos budget — considerar escalar
```

### Exemplo com breakdown por placement

```
Breakdown por Placement — Campanha: {prefixo}_ebooks_cadastros_lp
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Plataforma        | Posição          | Gasto     | Leads | CPL       | CPM
facebook          | feed             | R$ 120,00 | 9     | R$ 13,33  | R$ 17,50
instagram         | stream           | R$ 95,00  | 7     | R$ 13,57  | R$ 18,00
instagram         | reels            | R$ 80,00  | 5     | R$ 16,00  | R$ 21,00
facebook          | reels            | R$ 35,00  | 1     | R$ 35,00  | R$ 28,00
audience_network  | classic          | R$ 20,00  | 1     | R$ 20,00  | R$ 15,00
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏆 Melhor CPL: Facebook Feed (R$ 13,33)
⚠️  Pior CPL: Facebook Reels (R$ 35,00)
💡 Oportunidade: excluir Facebook Reels do posicionamento manual
```

### Exemplo breakdown demográfico

```
Breakdown Demográfico
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Idade     | Gênero | Gasto     | Leads | CPL       | CTR
25–34     | F      | R$ 80,00  | 7     | R$ 11,43  | 2,8%
35–44     | F      | R$ 95,00  | 8     | R$ 11,88  | 2,5%
35–44     | M      | R$ 60,00  | 3     | R$ 20,00  | 1,9%
45–54     | F      | R$ 70,00  | 4     | R$ 17,50  | 1,7%
45–54     | M      | R$ 45,00  | 1     | R$ 45,00  | 1,1%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏆 Melhor: Mulheres 25–34 (CPL R$ 11,43)
⚠️  Pior: Homens 45–54 (R$ 45,00 — 4x maior)
💡 Oportunidade: ad set exclusivo pra mulheres 25–44 com mais budget
```

---

## 8. Async Reports

Usar quando:
- Período > 30 dias a `level=ad`
- Breakdowns combinados gerarem muitas linhas
- Sync retornar timeout / rate limit

### Passo 1 — Criar

```bash
payload_form=(
  "fields=impressions,reach,spend,actions,cost_per_action_type,cpm,ctr"
  "date_preset=last_90d"
  "level=ad"
  "breakdowns=publisher_platform,platform_position"
)
# graph_api aceita body JSON ou form; pra async report Meta espera form-encoded:
report_run_id=$(graph_api POST "act_${AD_ACCOUNT_ID#act_}/insights" "$(IFS='&'; echo "${payload_form[*]}")" | jq -r .report_run_id)
```

### Passo 2 — Polling (30s)

```bash
while :; do
  r=$(graph_api GET "${report_run_id}")
  status=$(echo "$r" | jq -r .async_status)
  pct=$(echo "$r" | jq -r .async_percent_completion)
  echo "[$pct%] $status"
  [[ "$status" == "Job Completed" ]] && break
  [[ "$status" == "Job Failed" ]] && { echo "FAIL"; exit 1; }
  sleep 30
done
```

### Passo 3 — Resultados

```bash
graph_api GET "${report_run_id}/insights"
```

> **Timeout:** se após 10 minutos não concluir, informar e sugerir reduzir período/breakdowns.

---

## 9. Erros — referência

Catálogo completo em `lib/error-catalog.yaml` (inclui `3018` — data fora de 37 meses, e timeout com dica de async report). Tratamento automático via `error-resolver.sh`.

---

## 10. Referência de date_preset

```
today, yesterday
last_3d, last_7d, last_14d, last_28d, last_30d
this_month, last_month
this_quarter, last_quarter
maximum (limitado a 37 meses)
```

---

## 11. Perguntas Abertas → Fluxo

| Pergunta | Ação |
|----------|------|
| "Como tá a performance?" | Conta, `last_7d`, sem breakdown |
| "Quanto gastei esse mês?" | Conta, `this_month`, `spend,impressions,reach` |
| "Qual campanha tá indo melhor?" | Conta, `last_7d`, `level=campaign` |
| "Por que o CPA subiu?" | Campanha, `last_14d`, breakdown `age,gender`+`publisher_platform` |
| "Qual placement converte mais?" | Campanha, `last_14d`, breakdown `publisher_platform,platform_position` |
| "Qual público tá performando?" | `level=adset`, `last_7d`, sem breakdown |
| "Qual criativo tá indo melhor?" | `level=ad`, `last_7d`, sem breakdown |
| "Tá valendo continuar?" | Conta, `last_30d`, comparar ROAS/CPL vs meta |
