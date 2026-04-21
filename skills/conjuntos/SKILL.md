---
name: meta-ads-conjuntos
description: Ad sets Meta Ads com 5 destinos (Site/LeadForm/WhatsApp/Messenger/Call), targeting (geo/idade/interesses/lookalike), dayparting, frequency cap. Fix do bug #2 (advantage_audience obrigatório). Geocode via ViaCEP + Nominatim. CRUD completo — criar, listar, editar, pausar/ativar, deletar.
---

# meta-ads-conjuntos

Criação e gerenciamento de ad sets com targeting inteligente e 5 destinos suportados. Invocada pela orquestradora ou direto via `/meta-ads-conjuntos`.

## Modos

- **Criar** — fluxo interativo de 11 passos (default)
- **Listar** — `/meta-ads-conjuntos list [campaign_id]`
- **Editar** — `/meta-ads-conjuntos edit {id}`
- **Pausar/Ativar** — `/meta-ads-conjuntos pause|activate {id}`
- **Deletar** — `/meta-ads-conjuntos delete {id}` (só se PAUSED)

## Fluxo de criação (11 passos)

### Passo 1 — Pre-flight + contexto

Assume que o preflight (`lib/preflight.sh`) já rodou via orquestradora e que `CURRENT_RUN_ID`, `AD_ACCOUNT_ID`, `PAGE_ID` estão no env (vêm do CLAUDE.md).

Recebe `CAMPAIGN_ID` da orquestradora/user (`LAST_CAMPAIGN_ID` se encadeado depois de `/meta-ads-campanha`). Valida:

```bash
graph_api GET "${CAMPAIGN_ID}?fields=id,name,status,objective,is_adset_budget_sharing_enabled,daily_budget"
```

- Campanha tem que existir.
- Tem que estar `PAUSED` (cria ad set em campanha ativa dispara auto-spend sem revisão).
- Se `is_adset_budget_sharing_enabled == true` (CBO) → budget é da campanha, ad set não manda `daily_budget`.
- Se CBO e campanha sem `daily_budget` → erro, aborta (bug #1 do Filipe em variante CBO).

Se invocada direta (sem orquestradora), roda `source lib/preflight.sh; preflight_silent` antes.

### Passo 2 — Destino (5 opções)

```
Qual o destino das conversões?

[1] 🌐 Site externo           — tráfego/conversão pra landing externa
[2] 📋 Lead Form (Meta)       — form nativo do Facebook/Instagram
[3] 💬 WhatsApp               — abre conversa no WA Business
[4] 💬 Messenger              — abre conversa no Messenger
[5] 📞 Chamada telefônica     — toca botão que liga direto
```

Mapeamento pro payload:

| # | Destino | `destination_type` | `optimization_goal` | `billing_event` | CTA ad (setado no anúncio) | `promoted_object` |
|---|---------|--------------------|--------------------|-----------------|----------------------------|-------------------|
| 1 | Site externo | `WEBSITE` | `LINK_CLICKS` / `LANDING_PAGE_VIEWS` / `OFFSITE_CONVERSIONS` | `IMPRESSIONS` | `LEARN_MORE` / `SIGN_UP` / `SHOP_NOW` | `{pixel_id}` (se OFFSITE_CONVERSIONS) |
| 2 | Lead Form | `ON_AD` | `LEAD_GENERATION` / `QUALITY_LEAD` | `IMPRESSIONS` | `SIGN_UP` | `{page_id}` |
| 3 | WhatsApp | `WHATSAPP` | `CONVERSATIONS` | `IMPRESSIONS` | `WHATSAPP_MESSAGE` | `{page_id}` |
| 4 | Messenger | `MESSENGER` | `CONVERSATIONS` | `IMPRESSIONS` | `MESSENGER` | `{page_id}` |
| 5 | Call | `PHONE_CALL` | `QUALITY_CALL` | `IMPRESSIONS` | `CALL_NOW` | `{page_id}` |

Regras específicas por destino:

- **LEAD_FORM (2):** aciona `/meta-ads-lead-forms` antes pra criar form (se ainda não existe) e retorna `form_id`. Armazena em `LAST_FORM_ID` — o ad vai referenciar depois.
- **WHATSAPP (3):** valida ANTES do POST que a page tem WA Business conectado (evita erro 1838202):
  ```bash
  graph_api GET "${PAGE_ID}?fields=connected_whatsapp_business_account"
  ```
  Se vazio → bloqueia com msg: `✗ Page ${PAGE_ID} não tem WhatsApp Business conectado. Conecte em https://business.facebook.com/ antes de continuar.`
- **SITE (1) com OFFSITE_CONVERSIONS:** exige `PIXEL_ID` no CLAUDE.md + pergunta qual evento do pixel otimizar (`PURCHASE`, `LEAD`, `COMPLETE_REGISTRATION` etc.) → vai no `promoted_object.custom_event_type`.
- **CALL (5):** pergunta número (E.164, ex: `+5581999999999`) — vai no `promoted_object.phone_number` (ou só no ad dependendo da placement).

Salva em `ADSET_DESTINATION` e `ADSET_DEST_TYPE`.

### Passo 3 — Geolocalização

```
Qual localização?

[1] Cidade(s) — digite nomes (ex: "Recife, Olinda")
[2] CEP + raio — ex: "66055-190 + 15km"
[3] Estado/País inteiro — ex: "BR", "PE"
[4] Raio de endereço específico — "Av Boa Viagem 123, Recife + 5km"
```

**Opção 2 (CEP + raio) — geocode obrigatório:**

```bash
# 1. ViaCEP pra normalizar (valida que CEP existe + pega logradouro/cidade)
cep_clean=$(echo "$cep" | tr -d '-')
viacep=$(curl -sS "https://viacep.com.br/ws/${cep_clean}/json/")

# Se vier {"erro":true} → CEP inválido, pede de novo
if echo "$viacep" | jq -e '.erro' >/dev/null 2>&1; then
  echo "✗ CEP ${cep_clean} não existe no ViaCEP. Confere o número."
  return 1
fi

# 2. Nominatim pra converter pra lat/lng (User-Agent obrigatório, rate limit 1 req/s)
endereco=$(echo "$viacep" | jq -r '"\(.logradouro), \(.bairro), \(.localidade), \(.uf), Brasil"')
geo=$(curl -sS -G \
  -H "User-Agent: meta-ads-pro/1.0 (${NOMINATIM_EMAIL:-contato@example.com})" \
  --data-urlencode "q=${endereco}" \
  --data-urlencode "format=json" \
  --data-urlencode "limit=1" \
  --data-urlencode "countrycodes=br" \
  "https://nominatim.openstreetmap.org/search")

lat=$(echo "$geo" | jq -r '.[0].lat // empty')
lng=$(echo "$geo" | jq -r '.[0].lon // empty')

# Fallback se offline / Nominatim down: pergunta lat/lng manual
if [[ -z "$lat" || -z "$lng" ]]; then
  echo "⚠ Nominatim indisponível. Cola lat,lng manual (ex: -8.0476,-34.8770):"
  read -r manual
  lat="${manual%%,*}"
  lng="${manual#*,}"
fi

sleep 1  # respeita rate limit do Nominatim (1 req/s)
```

Payload final pra CEP/endereço:

```json
{
  "targeting": {
    "geo_locations": {
      "custom_locations": [
        {
          "latitude": -8.0476,
          "longitude": -34.8770,
          "radius": 15,
          "distance_unit": "kilometer",
          "address_string": "66055-190, Recife, PE"
        }
      ],
      "location_types": ["home", "recent"]
    }
  }
}
```

**Opção 1 (cidades):** resolve via `search?type=adgeolocation&location_types=["city"]`:

```bash
graph_api GET "search?type=adgeolocation&q=Recife&location_types=[\"city\"]&limit=5"
# → usa .data[].key como city_key
```

Payload: `geo_locations.cities: [{key: "CITY_KEY", radius: 10, distance_unit: "kilometer"}]`.

**Opção 3 (país/estado):** `geo_locations.countries: ["BR"]` ou `geo_locations.regions: [{key: "REGION_KEY"}]`.

**Opção 4 (endereço + raio):** pula ViaCEP, vai direto Nominatim com a string do endereço completo.

### Passo 4 — Idade

```
Faixa etária? (default 18-65)
[1] 18-65 (default — deixa Meta otimizar)
[2] Custom — digite "min-max" (ex: "25-45")
```

Payload: `age_min: 18`, `age_max: 65` (Meta aceita 13-65, mas negócios BR padrão é 18+).

### Passo 5 — Gênero

```
Gênero?
[1] Todos (default)
[2] Masculino
[3] Feminino
```

Mapeamento Meta: `genders: [1, 2]` (todos) / `genders: [1]` (masculino) / `genders: [2]` (feminino).

Se Todos → **omite** o campo `genders` (não envia `[1, 2]` porque Meta trata ausência = todos e evita warnings).

### Passo 6 — Interesses / Lookalike / Broad

```
Tipo de público?
[1] Interesses — Meta sugere baseado em keywords
[2] Lookalike — audiência similar a uma semente (custom audience)
[3] Broad — sem interesses, só geo + idade + gênero (Meta otimiza do zero)
[4] Custom Audience direta — selecionar audiência salva
```

**[1] Interesses:** pergunta keywords separadas por vírgula. Busca via:

```bash
graph_api GET "search?type=adinterest&q=Marketing%20Digital&limit=10"
# Mostra top 10, user escolhe N (múltiplos).
```

Payload: `flexible_spec: [{interests: [{id: "6003107902433", name: "Marketing digital"}]}]`.

**[2] Lookalike:** lista custom audiences salvas (via `/meta-ads-publicos`):

```bash
graph_api GET "${AD_ACCOUNT_ID}/customaudiences?fields=id,name,subtype,approximate_count_lower_bound&limit=50"
```

Filtra por `subtype == LOOKALIKE`. User escolhe. Payload: `custom_audiences: [{id: "AUD_ID"}]`.

**[3] Broad:** omite `flexible_spec` e `custom_audiences` — apenas geo/age/gender.

**[4] Custom Audience direta:** igual lookalike mas inclui todos os subtypes (CUSTOM, WEBSITE, ENGAGEMENT etc.).

### Passo 7 — Posicionamentos (placements)

```
Posicionamentos?
[1] Automáticos (default — Meta escolhe)
[2] Manual — escolher cada um
```

Se manual, multi-select:

```
[ ] Facebook Feed        [ ] Instagram Feed
[ ] Facebook Stories     [ ] Instagram Stories
[ ] Facebook Reels       [ ] Instagram Reels
[ ] Instagram Explore    [ ] Instagram Explore Grid (sibling obrigatório)
[ ] Messenger Stories    [ ] Audience Network
```

**Regras de sibling (fix bug de placement):**
- Se user escolhe `instagram_explore` → força adicionar `instagram_explore_grid_home` (erro 100/3858082).
- Se user escolhe Reels (`instagram_reels`/`facebook_reels`) → força `instream_video` sibling (erro 100/3858083).

Payload:

```json
{
  "targeting": {
    "publisher_platforms": ["facebook", "instagram"],
    "facebook_positions": ["feed", "story", "reels"],
    "instagram_positions": ["stream", "story", "reels", "explore", "explore_grid_home"]
  }
}
```

Se automático → omite `publisher_platforms`/`*_positions` (Meta aplica automatic placements).

### Passo 8 — Advantage Audience (FIX BUG #2)

**SEMPRE presente no payload de todo POST de ad set.** Independente de o user querer expansão ou não:

```json
{
  "targeting": {
    "targeting_automation": {
      "advantage_audience": 0
    }
  }
}
```

Pergunta opcional ao user:

```
Permitir Meta expandir audiência além das restrições? (Advantage+ Audience)
[1] Não (default — respeita exatamente o targeting configurado)
[2] Sim — Meta pode expandir interesses/idade/gênero se achar pessoas mais prováveis de converter
```

Mapeamento: `[1] → 0`, `[2] → 1`. **Nunca omite o campo** — omissão dispara erro 100/1870227 em algumas combinações de objective+destination_type (caso Filipe).

Validação final antes do POST (defensiva, mesmo que `targeting_automation` tenha sido seteado):

```bash
# Garante que advantage_audience está no JSON mesmo se user editar payload
targeting=$(echo "$targeting" | jq '.targeting_automation.advantage_audience //= 0')
```

### Passo 9 — Estimativa de alcance

Antes de confirmar, mostra alcance estimado:

```bash
# Monta objeto de targeting sem os campos não-estimáveis
estimate_targeting=$(echo "$targeting" | jq 'del(.targeting_automation)')

graph_api GET "${AD_ACCOUNT_ID}/reachestimate?targeting_spec=$(echo "$estimate_targeting" | jq -c . | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read()))')&optimization_goal=${OPT_GOAL}"
```

Renderiza:

```
📊 Alcance estimado (7 dias):
   Pessoas:   120.000 – 150.000
   Impressões: ~4.5M – 6.2M  (com budget atual)
   CPM est:   R$ 12 – R$ 18
```

Se `users_lower_bound < 1000` → warning: "Audiência muito restrita (<1k). Considera expandir geo/interesses."

### Passo 10 — Dayparting / Frequency cap (opcional)

```
Restrições de horário ou frequência? (default: nenhuma)
[1] Nenhuma
[2] Dayparting — mostrar só em horários específicos
[3] Frequency cap — limitar vezes que pessoa vê o anúncio
[4] Ambos
```

**Dayparting:**

Usa `pacing_type: ["day_parting"]` + `adset_schedule` (array de janelas; minutos do dia 0-1440):

```json
{
  "pacing_type": ["day_parting"],
  "adset_schedule": [
    {
      "start_minute": 480,       // 08:00
      "end_minute": 1200,        // 20:00
      "days": [1, 2, 3, 4, 5],   // seg-sex (0=domingo)
      "timezone_type": "USER"
    }
  ]
}
```

Pergunta em UI amigável ("Qual horário? Quais dias?") e converte pra minutos.

**Frequency cap** (requer `billing_event: IMPRESSIONS` — já default):

```json
{
  "frequency_control_specs": [
    {
      "event": "IMPRESSIONS",
      "interval_days": 7,
      "max_frequency": 3
    }
  ]
}
```

Pergunta: `Máximo de impressões por pessoa? (ex: 3 em 7 dias)`.

### Passo 11 — Preview + POST

**Preview ASCII (default):**

```
┌─ PREVIEW AD SET ─────────────────────────────────┐
│ Nome:        {gen_name adset ...}                 │
│ Campanha:    {camp_name} ({camp_id})              │
│ Destino:     WhatsApp (WHATSAPP / CONVERSATIONS)  │
│ Budget:      R$ 15/dia                            │
│ Geo:         Recife + 15km (-8.05, -34.88)        │
│ Idade:       25-45                                │
│ Gênero:      Todos                                │
│ Interesses:  Marketing digital, Empreendedorismo  │
│ Placements:  Automáticos                          │
│ Advantage:   OFF (advantage_audience=0) ← bug #2  │
│ Alcance:     120k–150k pessoas                    │
│ Dayparting:  Seg-Sex 08h-20h                      │
│ Frequency:   3x em 7 dias                         │
│ Status:      PAUSED                               │
└──────────────────────────────────────────────────┘

Confirma criação? [s/n/p=preview HTML com mapa]
```

**Preview HTML (`p`):** delega pra `lib/visual-preview.sh preview_html_adset "$payload"` — gera HTML com mapa Leaflet centrado na lat/lng e stats.

**POST final** quando user confirma (`s`):

```bash
# Nome via nomenclatura
name=$(gen_name adset "${NOMENCLATURA_STYLE}" \
  tipopublico="interesse" \
  nomeaudiencia="mkt-digital" \
  idade="25-45" \
  genero="todos" \
  regiao="recife-15km" \
  publico="interesse-mktdigital" \
  NN="01")

# Payload completo
payload=$(jq -nc \
  --arg n "$name" \
  --arg c "$CAMPAIGN_ID" \
  --arg dt "$destination_type" \
  --arg og "$optimization_goal" \
  --arg be "IMPRESSIONS" \
  --argjson db "$daily_budget_cents" \
  --argjson tg "$targeting" \
  --argjson po "$promoted_object" \
  --argjson sched "$adset_schedule" \
  --argjson freq "$frequency_control_specs" \
  --argjson idc "$is_dynamic_creative" \
  '{
    name: $n,
    campaign_id: $c,
    status: "PAUSED",
    destination_type: $dt,
    optimization_goal: $og,
    billing_event: $be,
    daily_budget: $db,
    targeting: ($tg | .targeting_automation.advantage_audience //= 0),
    promoted_object: $po,
    is_dynamic_creative: $idc
  } + (if $sched != null then {pacing_type:["day_parting"], adset_schedule: $sched} else {} end)
    + (if $freq != null then {frequency_control_specs: $freq} else {} end)')

# Se CBO na campanha, REMOVE daily_budget (budget fica na campanha)
if [[ "$CAMPAIGN_IS_CBO" == "true" ]]; then
  payload=$(echo "$payload" | jq 'del(.daily_budget)')
fi

graph_api POST "${AD_ACCOUNT_ID}/adsets" "$payload"
```

Após 200/201:

1. Lê `id` da resposta.
2. `manifest_add adset $adset_id` (rollback sabe que ad set foi criado).
3. Exporta `LAST_ADSET_ID=$adset_id` pra `/meta-ads-anuncios` encadear.
4. `telemetry_log adset_created id=$adset_id destination=$destination_type optimization=$optimization_goal advantage_audience=0`.

## Listar

```bash
graph_api GET "${AD_ACCOUNT_ID}/adsets?fields=id,name,status,campaign_id,destination_type,optimization_goal,daily_budget,effective_status&limit=50"
```

Ou filtrado por campanha:

```bash
graph_api GET "${CAMPAIGN_ID}/adsets?fields=id,name,status,destination_type,daily_budget&limit=50"
```

Tabela ASCII: id · name · status · destino · budget.

## Editar

`/meta-ads-conjuntos edit {id}` permite alterar:
- `name`
- `daily_budget`
- `targeting` (abre fluxo simplificado — só o que user quer mudar)
- `adset_schedule` / `frequency_control_specs`

**IMPORTANTE:** toda edição de targeting re-envia `targeting.targeting_automation.advantage_audience` (mesmo que já exista no ad set — algumas APIs regeneram o objeto inteiro).

## Pausar / Ativar

```bash
graph_api POST "{id}" '{"status":"PAUSED"}'
graph_api POST "{id}" '{"status":"ACTIVE"}'
```

Se ativar → confirma com user que campanha pai também está ACTIVE (ad set ACTIVE em campanha PAUSED não veicula).

## Deletar

Mesma regra de campanha: só deleta se `status == PAUSED`.

```bash
graph_api GET "{id}?fields=status"
# se PAUSED → graph_api DELETE "{id}"
# se ACTIVE → bloqueia
```

## Regras

- Sempre `status: PAUSED` ao criar.
- **Sempre `targeting.targeting_automation.advantage_audience: 0` (ou 1 se user pediu expansão)** — FIX BUG #2. Payload é passado por `jq ... //= 0` como segunda linha de defesa.
- WhatsApp destination: checa `connected_whatsapp_business_account` ANTES do POST (evita erro 1838202).
- Lead Form destination: roda `/meta-ads-lead-forms` antes pra ter `form_id`.
- CBO (campanha com `is_adset_budget_sharing_enabled=true`): **remove** `daily_budget` do payload do ad set.
- Geocoding via ViaCEP + Nominatim com fallback pra input manual (offline).
- Rate limit do Nominatim: `sleep 1` entre requests. User-Agent obrigatório.
- `pacing_type: ["day_parting"]` só se `adset_schedule` presente.
- `frequency_control_specs` exige `billing_event: IMPRESSIONS` (default).
- `is_dynamic_creative` sincronizado com `/meta-ads-anuncios` (se ad vai ser dinâmico, seta `true` aqui).
- Placements com `instagram_explore` → adiciona `instagram_explore_grid_home` sibling.
- Placements com Reels → adiciona `instream_video` sibling.

## Erros específicos

Ver `lib/error-catalog.yaml`. Conjuntos:

- `100/1870227` — `advantage_audience` ausente → resolver adiciona `targeting.targeting_automation.advantage_audience=0` (**bug #2**).
- `100/3858082` — placement `instagram_explore` sem sibling `grid_home` → resolver adiciona.
- `100/3858083` — placement `reels` sem sibling `instream_video` → resolver adiciona.
- `1838202` — WA destination mas page sem WA Business → user action (blocker).
- `1487534` — daily_budget < min do account → aumenta pro mínimo.
- `1487390` — optimization_goal incompatível com objective → user action.
- `2635` — bid strategy conflitando com campanha → user action.
- `613/80004/17` — rate limit → retry automático (`graph_api.sh` + BUC header read).
