---
name: meta-ads-publicos
description: "CRUD completo de audiences no Meta Ads via Graph API. Use quando o usuário mencionar: criar público, audience, lookalike, público personalizado, custom audience, remarketing, público semelhante, video view audience, upload lista, CRM audience, engajadores, visitantes do site, pixel audience, lista de leads, lista de clientes, público de compradores, sugira públicos, quais públicos criar."
---

# /meta-ads-publicos — Públicos e Audiências

Gerencia todos os tipos de audiences no Meta Ads: Custom Audiences (website, engajamento, video view, CRM) e Lookalike Audiences. Inclui sugestões inteligentes por tipo de negócio e criação em sequência.

**Pré-requisito:** Credenciais carregadas pela orquestradora `meta-ads/`. Se chamado diretamente, execute o fluxo de credenciais da orquestradora antes de qualquer chamada à API.

**Wrapper único:** todas chamadas Graph API passam por `lib/graph_api.sh::graph_api` (inclui retry + `error-resolver` + token injection automático). **Nunca** chame `curl` direto.

**Nomenclatura:** todos os nomes sugeridos abaixo são *exemplos* — prefira invocar `lib/nomenclatura.sh::gen_name` com o template detectado no setup do projeto (pode ser padrão custom do cliente). Se o usuário pediu explicitamente um nome literal, respeite.

---

## 1. Operações Disponíveis

| Ação | Endpoint (via `graph_api`) | Método |
|------|----------------------------|--------|
| Listar custom audiences | `act_{id}/customaudiences?fields=name,subtype,approximate_count_lower_bound,approximate_count_upper_bound,delivery_status,time_created` | GET |
| Criar custom audience | `act_{id}/customaudiences` | POST |
| Criar lookalike | `act_{id}/customaudiences` com `lookalike_spec` | POST |
| Ler detalhes | `{audience_id}?fields=name,subtype,approximate_count_lower_bound,approximate_count_upper_bound,delivery_status,rule,time_created` | GET |
| Adicionar usuários | `{audience_id}/users` | POST |
| Remover usuários | `{audience_id}/users` | DELETE |
| Health check | `{audience_id}/health` | GET |
| Deletar | `{audience_id}` | DELETE |
| Listar saved audiences | `act_{id}/saved_audiences` | GET |

---

## 2. Tipos de Audience — Fluxo por Tipo

Ao criar um público, pergunte primeiro: **"Qual tipo de público você quer criar?"** e apresente as opções:

| # | Tipo | Quando usar |
|---|------|------------|
| 1 | **Website (Pixel)** | Pessoas que visitaram páginas específicas do site |
| 2 | **Engagement (IG/FB)** | Pessoas que interagiram com seu Instagram ou Página |
| 3 | **Video Views** | Pessoas que assistiram X% de um vídeo seu |
| 4 | **Customer File (CRM)** | Upload de lista de emails/telefones de clientes |
| 5 | **Lookalike** | Pessoas parecidas com um público existente |

---

### 2.1 Website (Pixel)

**Fluxo de coleta:**

1. "Qual URL ou evento do pixel você quer capturar?"
   - URL: ex. `/obrigado`, `/checkout`, `/landing-page`
   - Evento: ex. `Lead`, `Purchase`, `ViewContent`, `AddToCart`
2. "Quantos dias de retenção?" (1–180 dias)
   - Sugestão por tipo: visitantes gerais → 30d, leads → 180d, compradores → 180d, abandono de carrinho → 14d
3. Gerar nome via `gen_name` (ex. com template `[{TIPO}][{SLUG}][{DIAS}]`) ou usar um literal pedido pelo usuário. Exemplos sugeridos: `visitou-lp-30d`, `add-to-cart-14d`, `checkout-7d`, `comprou-180d`.

**JSON spec — Website (URL):**

```json
{
  "name": "visitou-lp-30d",
  "subtype": "WEBSITE",
  "retention_days": 30,
  "rule": {
    "inclusions": {
      "operator": "or",
      "rules": [
        {
          "event_sources": [{"id": "{pixel_id}", "type": "pixel"}],
          "retention_seconds": 2592000,
          "filter": {
            "operator": "and",
            "filters": [
              {"field": "url", "operator": "i_contains", "value": "/landing-page"}
            ]
          }
        }
      ]
    }
  }
}
```

**Operadores de filtro disponíveis:**

| Operador | Significado |
|----------|------------|
| `i_contains` | URL contém (case insensitive) — mais comum |
| `i_not_contains` | URL não contém |
| `equal` | URL exata |
| `not_equal` | URL diferente da exata |
| `starts_with` | URL começa com |
| `ends_with` | URL termina com |

**Para evento do pixel (ex: Lead):**

```json
{
  "name": "leads-180d",
  "subtype": "WEBSITE",
  "retention_days": 180,
  "rule": {
    "inclusions": {
      "operator": "or",
      "rules": [
        {
          "event_sources": [{"id": "{pixel_id}", "type": "pixel"}],
          "retention_seconds": 15552000,
          "filter": {
            "operator": "and",
            "filters": [
              {"field": "event", "operator": "equal", "value": "Lead"}
            ]
          }
        }
      ]
    }
  }
}
```

**Criar:**

```bash
source "$CLAUDE_PLUGIN_ROOT/lib/graph_api.sh"

payload=$(jq -nc --arg pixel "$PIXEL_ID" --arg slug "/landing-page" '{
  name:"visitou-lp-30d",
  subtype:"WEBSITE",
  retention_days:30,
  rule:{inclusions:{operator:"or",rules:[{
    event_sources:[{id:$pixel,type:"pixel"}],
    retention_seconds:2592000,
    filter:{operator:"and",filters:[{field:"url",operator:"i_contains",value:$slug}]}
  }]}}
}')

graph_api POST "act_${AD_ACCOUNT_ID#act_}/customaudiences" "$payload"
```

---

### 2.2 Engagement (IG/FB)

**Fluxo de coleta:**

1. "Qual tipo de engajamento?" — apresentar opções:

| Opção | Tipo | Descrição |
|-------|------|-----------|
| 1 | Engajou com a Página FB | Curtiu, comentou, compartilhou, clicou em qualquer post |
| 2 | Visitou o perfil do Instagram | Visitou o perfil IG (não necessariamente engajou) |
| 3 | Interagiu com post/anúncio IG | Curtiu, comentou, salvou, compartilhou post IG |
| 4 | Enviou mensagem (IG ou Messenger) | DM no Instagram ou Messenger |
| 5 | Salvou post IG | Salvou qualquer post do Instagram |

2. "Quantos dias de retenção?" (1–365 dias)
   - Sugestão padrão: 90 dias

**JSON spec — Engagement IG:**

```json
{
  "name": "engajadores-ig-90d",
  "subtype": "ENGAGEMENT",
  "retention_days": 90,
  "rule": {
    "inclusions": {
      "operator": "or",
      "rules": [
        {
          "event_sources": [{"id": "{instagram_user_id}", "type": "ig_object"}],
          "retention_seconds": 7776000,
          "filter": {
            "operator": "and",
            "filters": [
              {"field": "event", "operator": "equal", "value": "ig_user_interacted"}
            ]
          }
        }
      ]
    }
  }
}
```

**Eventos de engajamento disponíveis:**

| Evento | Fonte | Significado |
|--------|-------|------------|
| `page_engaged` | `page` (`page_id`) | Engajou com a Página do Facebook |
| `ig_user_interacted` | `ig_object` (`instagram_user_id`) | Interagiu com post/anúncio do IG |
| `ig_business_profile_visit` | `ig_object` (`instagram_user_id`) | Visitou o perfil do Instagram |
| `ig_user_messaged_business` | `ig_object` (`instagram_user_id`) | Enviou mensagem no IG |
| `ig_user_saved_post` | `ig_object` (`instagram_user_id`) | Salvou post do Instagram |
| `page_messaged` | `page` (`page_id`) | Enviou mensagem no Messenger |

---

### 2.3 Video Views

**Fluxo de coleta:**

1. "Qual porcentagem assistida?" — opções: 25%, 50%, 75%, 95%, 100% (ThruPlay)
2. "Qual a duração aproximada do vídeo?" — ex: 0-1min, 1-3min, 3-10min
3. "Quantos dias de retenção?" (1–365 dias) — sugestão padrão: 365d
4. "É do Facebook ou Instagram?" — FB ou IG

**Nomenclatura:** gerar via `gen_name` ou usar exemplo `{plataforma}_VV_{duracao}_{porcentagem}_{retencao}` (ex. `FB_VV_0-1min_95%_365D`).

**Mapeamento de porcentagem para evento de pixel:**

| % Assistida | Campo da API |
|------------|-------------|
| 25% | `video_view_25_percent` |
| 50% | `video_view_50_percent` |
| 75% | `video_view_75_percent` |
| 95% | `video_view_95_percent` |
| 100% / ThruPlay | `video_complete_view` |

**JSON spec — Video Views:**

```json
{
  "name": "FB_VV_0-1min_75%_365D",
  "subtype": "ENGAGEMENT",
  "retention_days": 365,
  "rule": {
    "inclusions": {
      "operator": "or",
      "rules": [
        {
          "event_sources": [{"id": "{page_id}", "type": "page"}],
          "retention_seconds": 31536000,
          "filter": {
            "operator": "and",
            "filters": [
              {"field": "event", "operator": "equal", "value": "video_view_75_percent"}
            ]
          }
        }
      ]
    }
  }
}
```

---

### 2.4 Customer File (CRM)

**Fluxo de coleta:**

1. "Onde está a lista de contatos?" — CSV, planilha, ou lista manual
2. "Quais campos você tem disponíveis?"

| Campo | Tipo | Deve ser hasheado? |
|-------|------|:-----------------:|
| Email | `EMAIL` | Sim (obrigatório) |
| Telefone | `PHONE` | Sim (obrigatório) |
| Primeiro nome | `FN` | Sim |
| Sobrenome | `LN` | Sim |
| Cidade | `CT` | Não |
| Estado | `ST` | Não |
| CEP | `ZIP` | Não |
| País | `COUNTRY` | Não |
| Data de nascimento | `DOBY` (ano) | Não |

3. Explicar hashing obrigatório:

> **Importante:** Email, telefone e nome precisam ser hasheados com SHA256 antes do upload. O Meta nunca recebe os dados brutos — só os hashes.

**Como hashear com bash:**

```bash
# Hashear um email
echo -n "email@exemplo.com" | shasum -a 256 | awk '{print $1}'

# Hashear um telefone (formato E.164 sem espaços: +5511999999999)
echo -n "+5511999999999" | shasum -a 256 | awk '{print $1}'

# Hashear um nome (lowercase, sem acentos)
echo -n "maria" | shasum -a 256 | awk '{print $1}'
```

**Preparo dos dados:**
- Remover espaços em branco extras
- Email: lowercase
- Telefone: formato E.164 (ex: `+5511999999999`)
- Nome/sobrenome: lowercase, sem acentos

**Passo 1 — Criar a audience:**

```bash
payload=$(jq -nc '{
  name:"lista-leads-crm",
  subtype:"CUSTOM",
  description:"Lista de leads do CRM",
  customer_file_source:"USER_PROVIDED_ONLY"
}')
audience_id=$(graph_api POST "act_${AD_ACCOUNT_ID#act_}/customaudiences" "$payload" | jq -r .id)
```

**Passo 2 — Fazer upload dos dados:**

```bash
users_payload=$(jq -nc '{
  payload:{
    schema:["EMAIL","PHONE","FN","LN"],
    data:[
      ["<sha256_email>","<sha256_phone>","<sha256_fn>","<sha256_ln>"]
    ]
  }
}')
graph_api POST "${audience_id}/users" "$users_payload"
```

**Nota:** Para listas grandes (acima de 10.000 registros), fazer upload em lotes de até 10.000 registros por chamada.

**Valores de `customer_file_source`:**
- `USER_PROVIDED_ONLY` — dados fornecidos diretamente pelos usuários (ex: cadastros)
- `PARTNER_PROVIDED_ONLY` — dados de parceiros/terceiros
- `USER_PROVIDED_AND_PARTNER_PROVIDED` — combinação

---

### 2.5 Lookalike

**Fluxo de coleta:**

**Passo 1 — Listar audiences existentes:**

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/customaudiences?fields=name,subtype,approximate_count_lower_bound,approximate_count_upper_bound"
```

Mostrar tabela: nome, tipo, tamanho estimado. Perguntar: "Qual público usar como origem do Lookalike?"

**Passo 2 — Coleta de parâmetros:**

1. "Qual a porcentagem de similaridade?" (1–20%)
   - 1% = mais parecido com a origem, menor volume
   - 5% = equilíbrio entre similaridade e volume
   - 10–20% = maior volume, menos parecido
   - **Sugestão:** começar com 1% para testar
2. "Qual país?" (ex: BR, US, AR)

**Nota importante:** O público de origem precisa ter **mínimo de 100 membros** para gerar um Lookalike. Abaixo disso, a API retornará erro — ver `lib/error-catalog.yaml`.

**Nomenclatura:** `gen_name` ou padrão sugerido `lal_{nome-origem}-{porcentagem}pct_{pais}` (ex. `lal_compradores-1pct_br`).

**JSON spec — Lookalike:**

```json
{
  "name": "lal_compradores-1pct_br",
  "subtype": "LOOKALIKE",
  "lookalike_spec": {
    "origin_audience_id": "{source_audience_id}",
    "ratio": 0.01,
    "country": "BR"
  }
}
```

**Tabela de ratio por porcentagem:**

| % desejado | valor `ratio` |
|-----------|--------------|
| 1% | `0.01` |
| 2% | `0.02` |
| 3% | `0.03` |
| 5% | `0.05` |
| 10% | `0.10` |
| 20% | `0.20` |

**Criar:**

```bash
payload=$(jq -nc --arg src "$SOURCE_AUDIENCE_ID" '{
  name:"lal_compradores-1pct_br",
  subtype:"LOOKALIKE",
  lookalike_spec:{origin_audience_id:$src,ratio:0.01,country:"BR"}
}')
graph_api POST "act_${AD_ACCOUNT_ID#act_}/customaudiences" "$payload"
```

---

## 3. Sugestões Inteligentes por Tipo de Negócio

Quando o usuário disser **"sugira públicos para mim"** ou **"quais públicos devo criar?"**, pergunte:

> "Qual o tipo do negócio/oferta?" — (1) Infoproduto/Lead gen, (2) E-commerce, (3) Serviços/Agendamento

---

### 3.1 Infoproduto / Lead Gen

| # | Nome (exemplo) | Tipo | Config |
|---|--------------|------|--------|
| 1 | `visitou-lp-30d` | Website | URL da LP, retenção 30 dias |
| 2 | `IG_VV_75%_365D` | Video Views | 75%+ assistido, 365 dias |
| 3 | `leads-crm-180d` | Customer File | Lista de leads do CRM |
| 4 | `engajadores-ig-90d` | Engagement IG | `ig_user_interacted`, 90 dias |
| 5 | `lal_compradores-1pct_br` | Lookalike | Origem: lista compradores, 1%, BR |
| 6 | `lal_leads-1pct_br` | Lookalike | Origem: lista de leads, 1%, BR |

**Fluxo:** mostrar → perguntar "criar todos em sequência?" → coletar parâmetros (URL, pixel_id, instagram_user_id via CLAUDE.md) → criar um por um com progresso → listar IDs finais.

---

### 3.2 E-commerce

| # | Nome (exemplo) | Tipo | Config |
|---|--------------|------|--------|
| 1 | `visitou-site-30d` | Website | Qualquer página do site, 30 dias |
| 2 | `add-to-cart-30d` | Website | Evento `AddToCart`, 30 dias |
| 3 | `compradores-180d` | Website | Evento `Purchase`, 180 dias |
| 4 | `lal_compradores-1pct_br` | Lookalike | Origem: compradores 180d, 1%, BR |
| 5 | `lal_add-to-cart-1pct_br` | Lookalike | Origem: add-to-cart 30d, 1%, BR |

---

### 3.3 Serviços / Agendamento

| # | Nome (exemplo) | Tipo | Config |
|---|--------------|------|--------|
| 1 | `visitou-pagina-servicos-30d` | Website | URL da página de serviços, 30 dias |
| 2 | `engajadores-ig-90d` | Engagement IG | `ig_user_interacted`, 90 dias |
| 3 | `leads-crm-180d` | Customer File | Lista de leads/agendamentos |
| 4 | `lal_leads-1pct_br` | Lookalike | Origem: lista de leads, 1%, BR |

---

## 4. Fluxo de Listagem

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/customaudiences?fields=name,subtype,approximate_count_lower_bound,approximate_count_upper_bound,delivery_status,time_created"
```

**Formatar resultado como tabela:**

```
Públicos da conta
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Nome                         | Tipo        | Tamanho est. | Criado em
visitou-lp-30d               | WEBSITE     | 1.200–1.400  | 2026-03-01
lal_compradores-1pct_br      | LOOKALIKE   | 250k–300k    | 2026-03-10
engajadores-ig-90d           | ENGAGEMENT  | 3.500–4.000  | 2026-02-15
lista-leads-crm              | CUSTOM      | 800          | 2026-01-20
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total: 4 públicos
```

**Saved Audiences:**

```bash
graph_api GET "act_${AD_ACCOUNT_ID#act_}/saved_audiences?fields=name,targeting,time_created"
```

---

## 5. Ler Detalhes de um Público

```bash
graph_api GET "${audience_id}?fields=name,subtype,approximate_count_lower_bound,approximate_count_upper_bound,delivery_status,rule,time_created"
graph_api GET "${audience_id}/health"
```

---

## 6. Gerenciar Usuários de um Público

**Adicionar usuários:**

```bash
payload=$(jq -nc '{payload:{schema:["EMAIL"],data:[["<sha256_email_1>"],["<sha256_email_2>"]]}}')
graph_api POST "${audience_id}/users" "$payload"
```

**Remover usuários:**

```bash
payload=$(jq -nc '{payload:{schema:["EMAIL"],data:[["<sha256_email_para_remover>"]]}}')
graph_api DELETE "${audience_id}/users" "$payload"
```

---

## 7. Deletar um Público

```bash
graph_api DELETE "${audience_id}"
```

Se o erro 2656 for retornado (público tem Lookalikes associados), `error-resolver` tenta automaticamente listar + deletar os Lookalikes filhos antes de retry. Se precisar resolver manualmente:

```bash
# Lookalikes associados:
graph_api GET "act_${AD_ACCOUNT_ID#act_}/customaudiences?fields=name,subtype,lookalike_spec&filtering=[{\"field\":\"subtype\",\"operator\":\"IN\",\"value\":[\"LOOKALIKE\"]}]"
```

---

## 8. Limites da Conta

| Tipo de Audience | Limite |
|-----------------|--------|
| Customer File (CRM) | **500** audiences |
| Website Audiences (pixel) | **10.000** audiences |
| Mobile App Audiences | **200** audiences |
| Lookalike Audiences | **500** audiences |

Avisar proativamente antes de criar quando o total estiver a ≥ 90% do limite.

---

## 9. Erros — referência

Catálogo completo com fixes automáticos em `lib/error-catalog.yaml` (resolvidos via `error-resolver.sh`, disparado transparentemente por `graph_api`). Erros frequentes específicos de públicos (`2656`, `2654`) estão catalogados lá com auto-fix/hints.

---

## 10. Padrão de Confirmação antes de Criar

Sempre mostrar resumo antes de executar POST de criação:

```
Público a ser criado:
├── Nome: visitou-lp-30d
├── Tipo: Website (Pixel)
├── Pixel: {pixel_name} ({pixel_id})
├── Filtro: URL contém "/landing-page"
├── Retenção: 30 dias
└── Status: será criado e preenchido automaticamente pelo pixel

Confirma criação? (s/n)
```

Para Lookalike:

```
Lookalike a ser criado:
├── Nome: lal_compradores-1pct_br
├── Tipo: Lookalike
├── Origem: lista-compradores-180d ({audience_id})
├── Tamanho da origem: ~1.200 membros ✓ (mínimo 100)
├── Similaridade: 1%
└── País: Brasil (BR)

Confirma criação? (s/n)
```
