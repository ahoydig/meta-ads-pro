---
name: meta-ads-lead-forms
description: CRUD de Meta Instant Forms (lead forms nativos). Valida política de privacidade bilíngue PT+EN em 3 camadas, força thank you qualificado+desqualificado, suporta qualifier/disqualifier + guard-rails de condicionais (dropdowns encadeados/branching — ver estado real no Passo 5), export de leads pra CSV. Fix dos bugs #7 (privacy Instagram) e #8 (thank you dupla).
---

# meta-ads-lead-forms

CRUD completo de Instant Forms (formulários nativos da Meta que abrem dentro do Facebook/Instagram em vez de redirecionar pra site externo).

## Operações

- **Criar** — fluxo interativo de 9 passos (default)
- **Listar** — `/meta-ads-lead-forms list` → `GET /{page_id}/leadgen_forms`
- **Editar** — `/meta-ads-lead-forms edit {form_id}` → duplica + edita (Meta não permite editar form com leads coletados)
- **Deletar** — `/meta-ads-lead-forms delete {form_id}`
- **Export leads** — `/meta-ads-lead-forms export {form_id}` → `GET /{form_id}/leads` + CSV

## Fluxo de criação (9 passos)

### Passo 1 — Pre-flight

Doctor `--silent`. Valida:
- `META_ACCESS_TOKEN` setado
- `PAGE_ID` setado no `.env`/`CLAUDE.md`
- Token com scope `pages_manage_ads` + `leads_retrieval`
- Page token disponível (POST `/leadgen_forms` exige page token, não user token)

Se falhar: aborta com instrução clara de como resolver.

### Passo 2 — Nome interno (obrigatório)

Max 60 chars. Em testes automatizados, forçar prefixo `TEST_`.

```
Nome interno do form (só você vê, max 60 chars): ____
```

### Passo 3 — Intro screen (OBRIGATÓRIO — fix parcial bug #8)

```
Preencha a tela de INTRO (aparece ANTES das perguntas):

Título (max 60 chars): ____
Descrição (max 300 chars): ____
Imagem de intro (opcional, caminho local ou URL): ____
```

Validação: título + descrição não podem estar vazios.

Payload:
```json
{
  "context_card": {
    "title": "...",
    "content": ["..."],
    "image_url": "..."
  }
}
```

### Passo 4 — Perguntas pre-filled

Checkboxes com default selecionados:

```
Quais campos pré-preencher do perfil Meta do usuário?

[x] Nome completo (FULL_NAME) — default
[x] E-mail (EMAIL) — default
[x] Telefone (PHONE) — default
[ ] Cidade (CITY)
[ ] Estado (STATE)
[ ] CEP (ZIP)
[ ] Data de nascimento (DOB)
[ ] Gênero (GENDER)
```

Payload:
```json
{
  "questions": [
    {"type": "FULL_NAME"},
    {"type": "EMAIL"},
    {"type": "PHONE"}
  ]
}
```

### Passo 5 — Perguntas customizadas (até 15)

Pra cada pergunta:

```
Tipo:
[s] short_answer — resposta livre
[m] multiple_choice — opções (2-10)

Label (max 200 chars): ____

Se multiple_choice:
  Opção 1: ____
  Opção 2: ____
  ...

Qualifier?
[q] Qualifica (resposta X = lead bom)
[d] Desqualifica (resposta X = lead ruim)
[n] Neutra (sem filtro)
```

**Segurança:** labels e option values vêm do usuário. Passar sempre via `jq --arg` ou stdin pro Python — nunca via heredoc (FU-1).

**Condicionais — estado real (spike 2026-07):** ver `docs/spikes/2026-07-leadform-avancado.md`,
seções 3-4, pra evidência completa. Resumo executivo:

- **Qualificar/desqualificar por resposta: SUPORTADO.** Não existe (nem precisa de) um campo
  nativo "esta opção qualifica/desqualifica" — o mecanismo real da Meta é o form inteiro ter só
  duas saídas possíveis, `thank_you_page` (lead qualificado) ou `disqualified_thank_you_page`
  (lead desqualificado). Marque a pergunta como `[q]`/`[d]` no fluxo acima só pra guiar QUAL thank
  you mostrar (decisão client-side, fora do payload); a implementação real são os Passos 7-8
  (thank you dupla, já obrigatória desde o fix do bug #8). Regressão: `test_10_qualifier_disqualifier`
  (`tests/08-lead-forms.sh`) — form com pergunta qualificadora MULTIPLE_CHOICE + thank you dupla,
  round-trip via GET confirma key/label/options intactos.

- **Dropdowns encadeados (pergunta B só aparece se A = X): PARCIAL.** Os campos
  `dependent_conditional_questions` (array) e `conditional_questions_group_id` (numeric string)
  são reais e validados pela API por schema/enum — não são "chave desconhecida". Mas o mecanismo
  completo exige um **"LeadGen Conditional Questions Group"** pré-existente, e o endpoint de
  criação desse recurso não está documentado publicamente (nem na referência oficial da Graph
  API, nem no guia de lead ads — 4 tentativas ao vivo no spike, cada uma revelando um requisito
  novo: enum de 15 `input_type` válidos pro aninhado, proibição de `input_type` na pergunta pai,
  um `conditional_questions_choices_id` obrigatório sem posição correta encontrada, e por fim um
  `conditional_questions_group_id` que precisa apontar pra um grupo real — erro final:
  `"(#100) Param questions[N][conditional_questions_group_id] is not a valid LeadGen Conditional
  Questions Group ID"`). **Não implementar via payload JSON direto** — o artigo de ajuda da Meta
  sugere que esse grupo é criado pela UI do Ads Manager/Forms Library. **Pista futura:** criar um
  form com respostas condicionais na UI e inspecionar via `GET {form_id}?fields=questions` pra
  descobrir o formato real do `conditional_questions_group_id` e replicar.

- **Branching (mostrar/ocultar pergunta) fora da família acima: NÃO EXISTE.** Teste dedicado ao
  vivo com 3 candidatos (`visibility_condition`, `show_if`, `skip_logic`) numa mesma pergunta
  CUSTOM foi rejeitado com `"(#100) Invalid keys \"visibility_condition, show_if, skip_logic\"
  were found in param \"questions[N]\""` — erro de chave desconhecida (não de schema), e zero
  form foi criado. Segunda perna: o guia oficial completo de lead ads não menciona show/hide,
  skip logic ou visibilidade condicional em nenhum lugar. **Plano B (já validado ao vivo):**
  qualificação por dropdown + `disqualified_thank_you_page` — mesma implementação do item acima.
  Isso não esconde/mostra perguntas subsequentes (é tudo perguntas fixas + 1 desfecho binário no
  final), mas é suficiente pra qualificação simples; insuficiente pra múltiplos ramos de pergunta.
  Guard-rail permanente: `test_11_conditional_logic` (`tests/08-lead-forms.sh`) reproduz a
  Tentativa 4 do spike (`conditional_questions_group_id` fake) e falha explicitamente se a API um
  dia aceitar — nesse caso, atualizar este documento e o spike antes de construir em cima disso.

Payload exemplo:
```json
{
  "questions": [
    {"type": "FULL_NAME"},
    {
      "type": "CUSTOM",
      "key": "procedure_interest",
      "label": "Qual procedimento?",
      "options": [
        {"value": "Extração", "key": "ext"},
        {"value": "Gengivoplastia", "key": "geng"}
      ]
    }
  ]
}
```

**Nota:** sem `input_type` de propósito — achado ao vivo (`test_08`/`test_09` em `tests/08-lead-forms.sh`):
qualquer `input_type` é chave inválida numa pergunta CUSTOM de topo nesta versão da API
(`(#100) Invalid keys "input_type" were found in param "questions[N]"`). A presença de `options[]`
já basta pra virar multiple_choice; sem `options[]`, vira short_answer por padrão. Cada `option`
precisa de `key` (sem ele, a API retorna erro 500 genérico).

### Passo 6 — Privacy policy URL (3 camadas bilíngue — FIX BUG #7)

```
URL da política de privacidade: ____
```

Valida via `lib/privacy-validator.sh::validate_privacy_url`:

- **Camada 1 — Blacklist:**
  - `instagram.com/*` (+ subdomains) → rejeita (caso Filipe)
  - `facebook.com/*/posts` → rejeita
  - `linktr.ee/*` → rejeita
  - `beacons.ai/*` → rejeita

- **Camada 2 — Estrutural:**
  - HEAD 200 obrigatório
  - Fallback GET se servidor retornar 405 Method Not Allowed
  - Se ambos falharem → rejeita

- **Camada 3 — Conteúdo bilíngue:**
  - Texto ≥ 300 chars (sem tags)
  - Pelo menos 1 heading (`<h1>`, `<h2>` ou `<title>`) com "privacid" ou "privacy"
  - Pelo menos 1 keyword PT (`privacidade`, `política de privacidade`, `dados pessoais`, `LGPD`, `lei 13.709`)
    OU EN (`privacy policy`, `personal data`, `GDPR`, `data protection`, `CCPA`)

Se rejeita, oferece:
1. Template LGPD pronto (link pro doc interno)
2. Opções de hospedagem rápida: Notion público, Google Docs público, Facebook Note, WordPress.com

Cache de 24h em `~/.claude/meta-ads-pro/cache/privacy/{sha256(url)}`. Invalidar via `invalidate_privacy_cache "$url"` se o user corrigir a página.

**IMPORTANTE:** validação SEMPRE antes do POST. Skill recusa criação se Camada 1/2/3 reprovar.

### Passo 7 — Thank you screen QUALIFICADO (OBRIGATÓRIO)

Usuário que PASSOU no filtro (qualificado) vai ver:

```
Título: ____
Descrição: ____

CTA button — tipos validados AO VIVO contra a Graph API v25.0
(spike docs/spikes/2026-07-leadform-avancado.md, seção 5):

  [1] Nenhum (NONE)              — sem botão. Único tipo que dispensa button_text.
  [2] Visitar site (VIEW_WEBSITE) — requer button_text + website_url (recebe UTM estático)
  [3] Ver no Facebook (VIEW_ON_FACEBOOK) — requer button_text
  [4] Ligar agora (CALL_BUSINESS) — requer button_text + business_phone_number
      (E.164 completo, ex. "+5511987654321") + country_code (alpha-2, ex. "BR").
      Os dois campos são exigidos JUNTOS — número sem country_code (ou número
      "fake" tipo +5511999999999) dá erro (#192) not a valid phone number.
  [5] Baixar arquivo (DOWNLOAD)  — requer button_text + website_url apontando
      pro arquivo (recebe UTM estático). NÃO usa gated_file.
  [6] WhatsApp (WHATSAPP)        — requer button_text apenas (mínimo aceito).
      RECOMENDAÇÃO DO FUNIL: sempre passar business_phone_number (E.164) +
      country_code (alpha-2) explícitos. Sem eles o form ainda cria, mas o
      clique presumivelmente aponta pro WhatsApp conectado à Página — esse
      comportamento de clique não foi verificado ao vivo (só a criação).
  [7] Código promocional (PROMO_CODE) — requer button_text apenas. Onde o
      código promocional em si é configurado NÃO foi descoberto no spike
      (nenhum campo de código foi exigido nem apareceu no round-trip via GET)
      — avisar o usuário dessa lacuna, não fabricar um campo.
  [8] Agendar no site (BOOK_ON_WEBSITE) — requer button_text + website_url
      (recebe UTM estático).

NÃO OFERECER — rejeitados ao vivo pela API nesta conta/versão:
  ✗ MESSAGE_BUSINESS     → erro: "(#100) This button type is not yet
                             supported for Thank You Page"
  ✗ SCHEDULE_APPOINTMENT → erro: "(#100) Appointment integration is missing
                             for Thank You Page" (exige integração de
                             agendamento pré-configurada na Página, não é só
                             uma URL)

[não verificado ao vivo] P2B_MESSENGER — existe no enum oficial da Graph API
  (referência developers.facebook.com/docs/graph-api/reference/page/leadgen_forms),
  mas não foi testado nesta conta (fora do orçamento do spike). Não oferecer
  no menu até confirmar em spike futuro.
```

**Achado do spike:** todo `button_type` diferente de `NONE` exige `button_text` — sem ele, erro `(#100) Button text is missing for Thank You Page`.

**UTM estático em VIEW_WEBSITE/DOWNLOAD/BOOK_ON_WEBSITE (OBRIGATÓRIO):**

Lead form NÃO suporta macros `{{campaign.name}}` — Meta resolve URL no momento da criação do form, não no leilão. Aplicar UTM estático em qualquer `website_url` desses 3 tipos:

```bash
source "$CLAUDE_PLUGIN_ROOT/lib/utm.sh"

if [[ "$button_type" == "VIEW_WEBSITE" || "$button_type" == "DOWNLOAD" || "$button_type" == "BOOK_ON_WEBSITE" ]]; then
  if is_external_url "$website_url"; then
    today=$(date +%Y%m%d)
    slug=$(slugify "$form_name")
    website_url=$(build_utm_url_static "$website_url" "${today}_${slug}" "meta-leadform" "trafego-pago")
  fi
fi
```

Resultado: `https://seusite.com/obrigado?utm_source=meta-leadform&utm_medium=trafego-pago&utm_campaign=20260424_form-clinica`

**Payload por tipo** (exemplos completos — `<...>` é placeholder a preencher):

```json
NONE:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"NONE"}}

VIEW_WEBSITE:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"VIEW_WEBSITE",
  "button_text":"<texto do botão>","website_url":"<url com UTM estático>"}}

VIEW_ON_FACEBOOK:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"VIEW_ON_FACEBOOK",
  "button_text":"<texto do botão>"}}

CALL_BUSINESS:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"CALL_BUSINESS",
  "button_text":"<texto do botão>","business_phone_number":"<+5511987654321>","country_code":"<BR>"}}

DOWNLOAD:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"DOWNLOAD",
  "button_text":"<texto do botão>","website_url":"<url do arquivo com UTM estático>"}}

WHATSAPP (recomendado pro funil — número explícito):
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"WHATSAPP",
  "button_text":"<texto do botão>","business_phone_number":"<+5511987654321>","country_code":"<BR>"}}

PROMO_CODE:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"PROMO_CODE",
  "button_text":"<texto do botão>"}}

BOOK_ON_WEBSITE:
{"thank_you_page": {"title":"<título>","body":"<descrição>","button_type":"BOOK_ON_WEBSITE",
  "button_text":"<texto do botão>","website_url":"<url de agenda com UTM estático>"}}
```

### Passo 8 — Thank you screen DESQUALIFICADO (OBRIGATÓRIO — FIX BUG #8)

Campo crítico que a skill atual pulava. Forçar preenchimento:

```
Usuário que NÃO passou no filtro (desqualificado) vai ver:

Título: ____ (ex: "Obrigado pelo interesse!")
Descrição: ____ (ex: "Nesse momento não temos vagas pro seu perfil. Siga no IG.")

CTA button — MESMO leque de 8 tipos aceitos do Passo 7 (NONE, VIEW_WEBSITE,
VIEW_ON_FACEBOOK, CALL_BUSINESS, DOWNLOAD, WHATSAPP, PROMO_CODE, BOOK_ON_WEBSITE
— campos obrigatórios e payloads idênticos aos do Passo 7), com uma regra extra:

**CTA distinto do qualificado.** O button_type do desqualificado não pode repetir
o do qualificado (ex.: qualificado = WHATSAPP → desqualificado tipicamente
VIEW_WEBSITE pro Instagram/site institucional, VIEW_ON_FACEBOOK, ou NONE).

Mesmas restrições do Passo 7 valem aqui: MESSAGE_BUSINESS e SCHEDULE_APPOINTMENT
continuam rejeitados pela API; P2B_MESSENGER continua [não verificado ao vivo].
```

Client-side check do CTA distinto (antes do POST):
```bash
qual_type=$(echo "$payload" | jq -r '.thank_you_page.button_type')
disq_type=$(echo "$payload" | jq -r '.disqualified_thank_you_page.button_type')
[[ "$qual_type" != "$disq_type" ]] \
  || { echo "✗ CTA do desqualificado precisa ser diferente do qualificado"; exit 1; }
```

**UTM estático aqui também:** mesmo `build_utm_url_static` usado no Passo 7, com slug derivado do form_name. Aplica em qualquer `website_url` dos tipos VIEW_WEBSITE/DOWNLOAD/BOOK_ON_WEBSITE do CTA desqualificado.

Payload (exemplo — VIEW_WEBSITE pro Instagram):
```json
{
  "disqualified_thank_you_page": {
    "title": "Obrigado!",
    "body": "Siga nosso Instagram",
    "button_type": "VIEW_WEBSITE",
    "button_text": "Ir pro Instagram",
    "website_url": "https://instagram.com/foo?utm_source=meta-leadform&utm_medium=trafego-pago&utm_campaign=20260424_form-clinica"
  }
}
```

**Se user tentar pular este passo, skill recusa criação com:**
> "Lead forms precisam de thank you QUALIFICADO E DESQUALIFICADO desde v1.0.0. Fix do caso Filipe (bug #8). Preencha o passo 8 ou cancele."

Client-side check (pré-POST):
```bash
# forma canônica: jq -e pra ambos campos
echo "$payload" | jq -e '.thank_you_page and .disqualified_thank_you_page' >/dev/null \
  || { echo "✗ thank you dupla obrigatória"; exit 1; }
```

### Passo 8.5 — Tracking parameters (OBRIGATÓRIO)

Todo form leva `tracking_parameters` — key-values que a Meta devolve grudados em
CADA lead (via API/webhook; conferir no GHL o que a integração nativa mapeia).

```bash
source "$CLAUDE_PLUGIN_ROOT/lib/utm.sh"
tp=$(build_tracking_parameters "$form_name")
payload=$(echo "$payload" | jq --argjson tp "$tp" '. + {tracking_parameters:$tp}')
```

Formato validado ao vivo no spike `docs/spikes/2026-07-leadform-avancado.md` (seção 1):
o POST aceita **objeto JSON** `{chave: valor}` (é isso que `build_tracking_parameters`
gera em `lib/utm.sh`); no GET, o mesmo dado volta como **array de pares**
`[{"key":"...","value":"..."}]`, não como o objeto original — round-trip confirmado
ao vivo lá e reconfirmado no teste `test_14_tracking_parameters_roundtrip`
(`tests/08-lead-forms.sh`). Qualquer código que ler `tracking_parameters` de volta da
API (parser de lead, `--edit`) precisa tratar esse formato de array, não o objeto de
entrada. Achado extra do mesmo spike: no lead em si, cada chave do
`tracking_parameters` vira **um campo próprio em `field_data`** (lado a lado com
`full_name`/`email`/etc.), não uma seção separada.

Mostrar os valores ao usuário no resumo pré-POST.

### Passo 9 — POST + manifest

```bash
# graph_api.sh já aplica retry + error-resolver + DRY_RUN
graph_api POST "${PAGE_ID}/leadgen_forms" "$payload"
```

**`follow_up_action_url` também recebe UTM estático** antes do POST (mesmo pattern do passo 7).

Payload final (montado via `jq -n`, nunca via heredoc):
```json
{
  "name": "TEST_...",
  "questions": [...],
  "context_card": {...},
  "thank_you_page": {...},
  "disqualified_thank_you_page": {...},
  "privacy_policy": {"url": "https://..."},
  "follow_up_action_url": "https://...?utm_source=meta-leadform&utm_medium=trafego-pago&utm_campaign=20260424_form-clinica",
  "tracking_parameters": {
    "utm_source": "meta-leadform",
    "utm_medium": "trafego-pago",
    "utm_campaign": "20260424_form-clinica"
  }
}
```

Retorna `form_id`. Registra no manifest:
```bash
python3 lib/_py/manifest.py add leadgen_form "$form_id" --meta "{\"name\":\"...\"}"
```

## Operações auxiliares

### `--list` — listar forms existentes

```bash
graph_api GET "${PAGE_ID}/leadgen_forms?fields=id,name,status,leads_count,created_time&limit=100"
```

Mostra tabela: `ID | Nome | Status | Leads coletados | Criado em`.

### `--edit {form_id}` — duplicar + editar

Meta não permite editar form com leads. Fluxo:
1. `GET /{form_id}?fields=name,questions,context_card,thank_you_page,disqualified_thank_you_page,privacy_policy,follow_up_action_url`
2. Mostra diff do que pode mudar
3. Cria form novo via duplicate (POST com payload modificado)
4. Opcional: deleta o antigo se `status = DRAFT`

### `--export {form_id}` — leads pra CSV

```bash
graph_api GET "${form_id}/leads?fields=id,created_time,field_data&limit=500"
```

Converte pra CSV via `python3 lib/_py/leads_to_csv.py`.

### `--delete {form_id}`

```bash
graph_api DELETE "${form_id}"
```

Remove do manifest.

## Regras invioláveis

1. **8 campos obrigatórios**, nenhum pode estar vazio:
   - `name`
   - `questions` (≥1 pre-filled)
   - `context_card`
   - `privacy_policy.url` (validada 3 camadas)
   - `thank_you_page`
   - `disqualified_thank_you_page`
2. **Privacy URL Instagram → rejeita** (blacklist — bug #7).
3. **Cache de validação privacy: 24h** via sha256 do URL.
4. **Thank you desqualificado SEMPRE obrigatório** (fix bug #8). Recusa client-side antes do POST.
5. **Page token** obrigatório pra POST (não user token).
6. **Zero echo/printf com `$META_ACCESS_TOKEN`** — usar sempre via `graph_api`.
7. **Labels/options user-controlled passam via `jq --arg` ou stdin**, nunca heredoc (FU-1).
8. **UTM estático obrigatório** em `thank_you_page.website_url`, `disqualified_thank_you_page.website_url` e `follow_up_action_url` (passos 7-8 + payload final). Padrão: `utm_source=meta-leadform&utm_medium=trafego-pago&utm_campaign={YYYYMMDD}_{form-slug}` via `lib/utm.sh::build_utm_url_static`. Lead form não aceita macros `{{}}` — Meta resolve URL no submit, não no leilão. **`tracking_parameters` também obrigatório** (passo 8.5) via `lib/utm.sh::build_tracking_parameters` — objeto JSON `{chave: valor}` no POST; volta como array `[{key,value}]` no GET e vira campo próprio no `field_data` de cada lead (formato validado ao vivo no spike `docs/spikes/2026-07-leadform-avancado.md`, seção 1).

## Erros específicos

Ver `lib/error-catalog.yaml`:
- `2657` — `form_id` inválido
- `100` sub `1487194` — privacy policy URL inválida (Meta-side double-check)
- `190` — token expirado/revogado
- `200` — scope faltando (`leads_retrieval` ou `pages_manage_ads`)
- `2656` — não pode deletar form com lookalikes dependentes

## Ganchos com outras skills

- **`flows/anuncios/`** — quando `destination_type=LEAD_FORM`, orquestradora aciona `/meta-ads-lead-forms` antes pra obter `form_id`, depois injeta em `object_story_spec.link_data.lead_gen_form_id`.
- **`lib/graph_api.sh`** — todos os calls HTTP passam por ele (retry + error-resolver + DRY_RUN).
- **`lib/privacy-validator.sh`** — validação 3 camadas com cache 24h.
- **`lib/rollback.sh`** — `rollback leadgen_form {form_id}` reverte criação.
