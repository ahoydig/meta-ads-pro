---
name: meta-ads-regras
description: "Criar e gerenciar regras automáticas de otimização no Meta Ads via Graph API. Use quando o usuário mencionar: criar regra, regra de otimização, pausar automático, pausar anuncio automaticamente, escalar campanha, automação meta ads, CPA alto, ROAS baixo, frequência alta, regras automatizadas, automated rules, notification rule, rebalancear budget, otimização automática, alerta de performance."
---

# /meta-ads-regras — Regras Automáticas de Otimização

Cria, gerencia e monitora automated rules no Meta Ads via Graph API. As regras permitem pausar, escalar, rebalancear e alertar automaticamente com base em métricas de performance.

---

## Pré-requisitos

Credenciais carregadas pela orquestradora `meta-ads/`. Se chamado direto, rodar fluxo de setup antes. Variáveis disponíveis em `AD_ACCOUNT_ID` (sem `act_` — adicione prefixo quando montar endpoint).

**Wrapper único:** todas chamadas Graph API passam por `lib/graph_api.sh::graph_api` (inclui retry + `error-resolver` + token injection automático). **Nunca** chame `curl` direto.

**Nomenclatura:** gerar nomes via `lib/nomenclatura.sh::gen_name` com template do projeto — os exemplos abaixo (`pausar-cpa-alto`, etc.) são apenas ilustrativos.

---

## 1. Operações Disponíveis

| Ação | Endpoint (via `graph_api`) | Método |
|------|----------------------------|--------|
| Criar regra | `act_{id}/adrules_library` | POST |
| Listar regras | `act_{id}/adrules_library?fields=name,status,schedule_spec,evaluation_spec,execution_spec` | GET |
| Ler regra | `{rule_id}?fields=name,status,schedule_spec,evaluation_spec,execution_spec` | GET |
| Editar regra | `{rule_id}` | POST |
| Histórico de execução | `{rule_id}/history` | GET |
| Deletar regra | `{rule_id}` | DELETE |

### Criar regra

```bash
source "$CLAUDE_PLUGIN_ROOT/lib/graph_api.sh"
graph_api POST "act_${AD_ACCOUNT_ID#act_}/adrules_library" "$payload"
```

### Listar regras

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/adrules_library?fields=name,status,schedule_spec,evaluation_spec,execution_spec"
```

### Ler regra específica

```bash
graph_api GET "${rule_id}?fields=name,status,schedule_spec,evaluation_spec,execution_spec"
```

### Editar regra

```bash
payload=$(jq -nc --arg n "novo-nome" '{name:$n,status:"ENABLED"}')
graph_api POST "${rule_id}" "$payload"
```

### Histórico / deletar

```bash
graph_api GET    "${rule_id}/history"
graph_api DELETE "${rule_id}"
```

---

## 2. Templates Prontos

Apresente os 6 templates ao usuário e pergunte qual deseja usar. Para cada template, preencha os valores entre `{}` com os parâmetros que o usuário informar.

---

### Template 1 — Pausar CPA Alto

**O que faz:** Pausa anúncios com custo por lead acima do limite, nos últimos 3 dias, com pelo menos 500 impressões.

**Quando usar:** Proteger orçamento de anúncios com CPA fora do alvo.

**Schedule:** A cada 30 minutos (`SEMI_HOURLY`).

```json
{
  "name": "pausar-cpa-alto",
  "evaluation_spec": {
    "evaluation_type": "SCHEDULE",
    "filters": [
      {"field": "entity_type", "value": "AD", "operator": "EQUAL"},
      {"field": "time_preset", "value": "LAST_3_DAYS", "operator": "EQUAL"},
      {"field": "cost_per", "value": 4500, "operator": "GREATER_THAN"},
      {"field": "impressions", "value": 500, "operator": "GREATER_THAN"}
    ]
  },
  "execution_spec": { "execution_type": "PAUSE" },
  "schedule_spec":  { "schedule_type":  "SEMI_HOURLY" }
}
```

**Parâmetros customizáveis:**
- `cost_per: 4500` → custo máximo por lead em centavos (R$ 45,00 = 4500)
- `time_preset: "LAST_3_DAYS"` → período de avaliação
- `impressions: 500` → mínimo de impressões para acionar

---

### Template 2 — Escalar Vencedor (+20% Budget)

**O que faz:** Aumenta orçamento diário em 20% nos conjuntos com CPA abaixo do alvo e >5 resultados nos últimos 3 dias, com teto.

**Schedule:** `DAILY`.

```json
{
  "name": "escalar-vencedor",
  "evaluation_spec": {
    "evaluation_type": "SCHEDULE",
    "filters": [
      {"field": "entity_type", "value": "ADSET", "operator": "EQUAL"},
      {"field": "time_preset", "value": "LAST_3_DAYS", "operator": "EQUAL"},
      {"field": "cost_per", "value": 3000, "operator": "LESS_THAN"},
      {"field": "results", "value": 5, "operator": "GREATER_THAN"}
    ]
  },
  "execution_spec": {
    "execution_type": "CHANGE_BUDGET",
    "execution_options": [
      {"field": "change_spec", "value": {"amount": 20, "unit": "PERCENTAGE", "limit": 50000}, "operator": "EQUAL"}
    ]
  },
  "schedule_spec": { "schedule_type": "DAILY" }
}
```

**Parâmetros customizáveis:**
- `cost_per: 3000` → CPA alvo máximo em centavos
- `results: 5` → mínimo de resultados
- `amount: 20` → percentual de aumento
- `limit: 50000` → orçamento máximo em centavos

---

### Template 3 — Pausar Sem Resultado

**O que faz:** Pausa anúncios que gastaram acima do limite nos últimos 3 dias sem gerar resultado.

**Schedule:** `SEMI_HOURLY`.

```json
{
  "name": "pausar-sem-resultado",
  "evaluation_spec": {
    "evaluation_type": "SCHEDULE",
    "filters": [
      {"field": "entity_type", "value": "AD", "operator": "EQUAL"},
      {"field": "time_preset", "value": "LAST_3_DAYS", "operator": "EQUAL"},
      {"field": "spent", "value": 5000, "operator": "GREATER_THAN"},
      {"field": "results", "value": 0, "operator": "EQUAL"}
    ]
  },
  "execution_spec": { "execution_type": "PAUSE" },
  "schedule_spec":  { "schedule_type":  "SEMI_HOURLY" }
}
```

---

### Template 4 — Alerta ROAS Baixo

**O que faz:** Notifica (sem pausar) quando ROAS de campanha cai abaixo do limite nos últimos 7 dias.

**Schedule:** `DAILY`.

```json
{
  "name": "alerta-roas-baixo",
  "evaluation_spec": {
    "evaluation_type": "SCHEDULE",
    "filters": [
      {"field": "entity_type", "value": "CAMPAIGN", "operator": "EQUAL"},
      {"field": "time_preset", "value": "LAST_7_DAYS", "operator": "EQUAL"},
      {"field": "purchase_roas:omni_purchase", "value": 2.0, "operator": "LESS_THAN"}
    ]
  },
  "execution_spec": { "execution_type": "NOTIFICATION" },
  "schedule_spec":  { "schedule_type":  "DAILY" }
}
```

---

### Template 5 — Pausar Frequência Alta

**O que faz:** Pausa conjuntos com frequência >3 nos últimos 7 dias (público saturado).

**Schedule:** `DAILY`.

```json
{
  "name": "pausar-frequencia-alta",
  "evaluation_spec": {
    "evaluation_type": "SCHEDULE",
    "filters": [
      {"field": "entity_type", "value": "ADSET", "operator": "EQUAL"},
      {"field": "time_preset", "value": "LAST_7_DAYS", "operator": "EQUAL"},
      {"field": "frequency", "value": 3, "operator": "GREATER_THAN"}
    ]
  },
  "execution_spec": { "execution_type": "PAUSE" },
  "schedule_spec":  { "schedule_type":  "DAILY" }
}
```

---

### Template 6 — Rebalancear CBO

**O que faz:** Rebalanceia orçamento entre conjuntos de uma campanha CBO por performance.

**Schedule:** `DAILY`.

```json
{
  "name": "rebalancear-cbo",
  "evaluation_spec": {
    "evaluation_type": "SCHEDULE",
    "filters": [
      {"field": "entity_type", "value": "CAMPAIGN", "operator": "EQUAL"},
      {"field": "time_preset", "value": "LAST_3_DAYS", "operator": "EQUAL"}
    ]
  },
  "execution_spec": { "execution_type": "REBALANCE_BUDGET" },
  "schedule_spec":  { "schedule_type":  "DAILY" }
}
```

---

## 3. Fluxo Interativo — Usar Template

### Passo 1 — Apresentar templates

```
Qual tipo de regra você quer criar?

1. Pausar CPA alto — a cada 30min
2. Escalar vencedor (+20%) — diário
3. Pausar sem resultado — a cada 30min
4. Alerta ROAS baixo — diário, sem pausar
5. Pausar frequência alta — diário
6. Rebalancear CBO — diário
7. Regra personalizada — guiado do zero
```

### Passo 2 — Coletar parâmetros customizáveis (conversão R$ → centavos onde aplicável).

### Passo 3 — Mostrar em linguagem natural (humanizada) antes de POST.

```
Regra: "Pausar CPA Alto"
Em palavras: Pausar automaticamente anúncios com custo por lead acima de R$ 45,00
             nos últimos 3 dias (mínimo 500 impressões), verificando a cada 30 min.

Confirma criação? (s/n)
```

### Passo 4 — Criar

```bash
graph_api POST "act_${AD_ACCOUNT_ID#act_}/adrules_library" "$payload"
```

Resposta bem-sucedida traz `id` da regra. Em falha, `error-resolver` tenta auto-fix ou apresenta hint.

---

## 4. Construtor de Regra Personalizada

Para regras além dos templates, guiar o usuário pelos três blocos:

### 4.1 — evaluation_spec (quando e o que avaliar)

```json
{
  "evaluation_type": "SCHEDULE",
  "filters": [
    {"field": "{campo}", "value": "{valor}", "operator": "{operador}"}
  ]
}
```

**evaluation_type:** `SCHEDULE` (segue `schedule_spec`) ou `TRIGGER` (dispara por evento).

#### Campos de filtro disponíveis

| Campo | Descrição | Tipo | Notas |
|-------|-----------|------|-------|
| `entity_type` | Tipo de entidade | `AD`, `ADSET`, `CAMPAIGN` | Usar operator `EQUAL` com string |
| `id` | IDs específicos | Array | Usar operator `IN` |
| `time_preset` | Período | ver tabela abaixo | |
| `spent` | Gasto total | centavos | **é `spent`, NÃO `spend`** |
| `impressions` | Impressões | inteiro | |
| `reach` | Alcance | inteiro | |
| `frequency` | Frequência | decimal | |
| `clicks` | Cliques | inteiro | |
| `ctr` | CTR | decimal (0.02=2%) | |
| `cpm` | CPM | centavos | |
| `cpc` | CPC | centavos | |
| `results` | Resultados | inteiro | |
| `cost_per` | Custo por resultado | centavos | **Campo genérico p/ CPA/CPL. NÃO usar `cost_per_result`** |
| `purchase_roas:omni_purchase` | ROAS | decimal | |
| `action_values:omni_purchase` | Valor de compras | centavos | |
| `video_p75_watched_actions` | Views 75% | inteiro | |
| `budget_remaining` | Orçamento restante | centavos | |
| `daily_budget` | Orçamento diário | centavos | |
| `lifetime_budget` | Orçamento vitalício | centavos | |

#### time_preset

| Valor | Período |
|-------|---------|
| `TODAY` / `YESTERDAY` | Hoje / Ontem |
| `LAST_3_DAYS`, `LAST_7_DAYS`, `LAST_14_DAYS`, `LAST_28_DAYS`, `LAST_30_DAYS` | Últimos N dias |
| `THIS_MONTH` / `LAST_MONTH` | Este mês / mês passado |

#### Operadores

| Operador | Significado |
|---------|-------------|
| `GREATER_THAN`, `LESS_THAN`, `EQUAL`, `NOT_EQUAL` | comparações |
| `IN`, `NOT_IN` | lista |
| `IN_RANGE`, `NOT_IN_RANGE` | intervalo `[min, max]` |
| `CONTAIN`, `NOT_CONTAIN` | texto |

#### Trigger types (quando `evaluation_type: TRIGGER`)

`METADATA_CREATION` · `METADATA_UPDATE` · `STATS_MILESTONE` · `STATS_CHANGE` · `DELIVERY_INSIGHTS_CHANGE`.

---

### 4.2 — execution_spec

| execution_type | O que faz |
|---------------|-----------|
| `PAUSE` / `UNPAUSE` | pausa / ativa |
| `CHANGE_BUDGET` | altera orçamento do ad set / campanha |
| `CHANGE_BID` | altera lance |
| `CHANGE_CAMPAIGN_BUDGET` | altera CBO |
| `REBALANCE_BUDGET` | redistribui entre conjuntos |
| `ROTATE` | rotaciona criativos |
| `NOTIFICATION` | notifica sem alterar |
| `PING_ENDPOINT` | POST pra endpoint externo |
| `LABEL` / `REMOVE_LABEL` | labels |
| `SEND_REPORT` | email de report |
| `PAUSE_AND_NOTIFY`, `UNPAUSE_AND_NOTIFY`, `CHANGE_BUDGET_AND_NOTIFY`, `CHANGE_BID_AND_NOTIFY` | combinadas |
| `BOOST_POST` | impulsiona post |

**CHANGE_BUDGET (valor fixo):**
```json
{
  "execution_type": "CHANGE_BUDGET",
  "execution_options": [
    {"field": "change_spec", "value": {"amount": 10000, "unit": "ACCOUNT_CURRENCY"}, "operator": "EQUAL"}
  ]
}
```

**CHANGE_BUDGET (percentual com teto):**
```json
{
  "execution_type": "CHANGE_BUDGET",
  "execution_options": [
    {"field": "change_spec", "value": {"amount": 20, "unit": "PERCENTAGE", "limit": 50000}, "operator": "EQUAL"}
  ]
}
```

`unit` aceita **`ACCOUNT_CURRENCY`** ou **`PERCENTAGE`** — `ABSOLUTE` NÃO existe.

**PING_ENDPOINT:**
```json
{
  "execution_type": "PING_ENDPOINT",
  "execution_options": [
    {"field": "endpoint", "value": "https://hooks.example.com/catch/xxxxx/", "operator": "EQUAL"}
  ]
}
```

---

### 4.3 — schedule_spec

> **Cooldown de 12h:** Meta aplica cooldown padrão por regra × entidade. Para rodar ação mais de 1× por dia numa mesma entidade, criar **regras separadas** (cada uma com seu horário).

| schedule_type | Frequência |
|--------------|-----------|
| `SEMI_HOURLY` | A cada 30 min |
| `HOURLY` | A cada 1h |
| `DAILY` | 1× por dia |
| `CUSTOM` | Horários específicos (`start_minute` em minutos desde meia-noite; `days` 0=dom…6=sab) |

**CUSTOM múltiplos horários (8h, 11h, 14h, 17h, 20h):**
```json
{
  "schedule_type": "CUSTOM",
  "schedule": [
    {"start_minute": 480,  "days": [0,1,2,3,4,5,6]},
    {"start_minute": 660,  "days": [0,1,2,3,4,5,6]},
    {"start_minute": 840,  "days": [0,1,2,3,4,5,6]},
    {"start_minute": 1020, "days": [0,1,2,3,4,5,6]},
    {"start_minute": 1200, "days": [0,1,2,3,4,5,6]}
  ]
}
```

---

## 5. Listagem e Histórico

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/adrules_library?fields=name,status,schedule_spec,evaluation_spec,execution_spec"
graph_api GET "${rule_id}/history"
```

Formatar listagem como tabela:

```
Regras automáticas ativas
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Nome                     | Status  | Tipo exec.    | Schedule
pausar-cpa-alto          | ENABLED | PAUSE         | SEMI_HOURLY
escalar-vencedor         | ENABLED | CHANGE_BUDGET | DAILY
alerta-roas-baixo        | ENABLED | NOTIFICATION  | DAILY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 6. Regras Invioláveis

- **SEMPRE** mostrar a regra em linguagem natural antes de criar
- **SEMPRE** pedir confirmação antes de POST
- **SEMPRE** verificar resposta por `error` antes de confirmar sucesso (o `graph_api` + `error-resolver` cuidam disso, mas eco final ao usuário deve validar o `id`)
- **NUNCA** criar `execution_type` destrutivo sem confirmar escopo
- Em erro, mostrar código + mensagem + sugestão (já vem do `error-resolver`)

---

## 7. Erros — referência

Catálogo completo com fixes automáticos em `lib/error-catalog.yaml` (inclui variantes do `100` específicas de regras: `spent` vs `spend`, `cost_per` vs `cost_per_result`, `IN` com `entity_type`, unit `ABSOLUTE` inexistente; e `1815047` nome duplicado, `2446884` limite de regras).
