# Spike: lead form avançado — condicionais, tracking_parameters, thank you CTAs (2026-07)

Spike ao vivo contra a Graph API v25.0 (conta `act_763408067802379`, Página `108356564252733`),
via `plugins/meta-ads-pro/lib/graph_api.sh`. Todo payload abaixo foi rodado de verdade
(nenhum é hipotético) — erros são colados verbatim das respostas da API. Trechos rotulados
`[doc]` vêm de WebFetch em páginas oficiais da Meta (URL citada); trechos sem rótulo são
evidência ao vivo desta sessão (2026-07-09).

## Os 4 vereditos (resumo executivo)

| # | Pergunta | Veredito | Detalhe |
|---|---|---|---|
| 1 | `tracking_parameters` — formato aceito? | **EXISTE** | Objeto `{chave: valor}` no POST; volta como array `[{key,value}]` no GET. Propaga pro `field_data` do lead como campos próprios. |
| 2 | `test_leads` — mecanismo? | **EXISTE** | `POST {form_id}/test_leads {}` cria um lead de teste com dados dummy automáticos. Limite: 1 por form (2ª chamada dá erro). |
| 3 | Dropdowns encadeados (pergunta CUSTOM com dependentes) | **PARCIAL** | Os campos (`dependent_conditional_questions`, `conditional_questions_group_id`) são reais e validados pela API, mas exigem um **"LeadGen Conditional Questions Group"** pré-existente cujo endpoint de criação não foi localizado (nem nos docs oficiais, nem por engenharia reversa dentro do orçamento do spike). Não é um payload standalone na criação do form. |
| 4 | Branching (mostrar/ocultar pergunta) | **NÃO EXISTE** como campo separado | Teste de API dedicado: candidatos `visibility_condition`/`show_if`/`skip_logic` rejeitados como chaves inválidas (erro verbatim na seção 4) + zero menção na doc oficial. Único mecanismo da família é o do item 3. Plano B: qualificação via dropdown + `disqualified_thank_you_page` (**já validado ao vivo, funciona**). |

CTA (`thank_you_page.button_type`) testados ao vivo: ver tabela completa na seção 5.

---

## 1. `tracking_parameters` — EXISTE, formato objeto

### Descoberta lateral: 2 campos ficaram obrigatórios nesta versão que o payload do brief não tinha

O payload mínimo do brief (`build_minimal_form_payload` + `tracking_parameters`) foi rejeitado
duas vezes antes de funcionar — ambos os requisitos batem com o schema oficial
(`fields context_card.style` e `thank_you_page.button_type` em
https://developers.facebook.com/docs/graph-api/reference/page/leadgen_forms):

```
POST {PAGE_ID}/leadgen_forms  (payload do brief, sem alteração)
→ {"error":{"message":"(#100) The parameter thank_you_page[button_type] is required.","type":"OAuthException","code":100}}
```

```
POST {PAGE_ID}/leadgen_forms  (+ thank_you_page.button_type:"NONE")
→ {"error":{"message":"(#100) Context card style is not provided","type":"OAuthException","code":100}}
```

`[doc]` `context_card.style` é `enum {LIST_STYLE, PARAGRAPH_STYLE}` — confirmado via WebFetch em
https://developers.facebook.com/docs/graph-api/reference/page/leadgen_forms.

### Payload que funcionou (system-user token — não precisou de page token)

```json
{
  "name": "TEST_SPIKE_1783571218",
  "questions": [{"type":"FULL_NAME"},{"type":"EMAIL"},{"type":"PHONE"}],
  "privacy_policy": {"url": "https://lp.ahoy.digital/politicas-privacidade"},
  "context_card": {"title":"Intro spike","content":["Descrição de introdução"],"style":"LIST_STYLE"},
  "thank_you_page": {"title":"Obrigado!","body":"Em contato em breve","button_type":"NONE"},
  "disqualified_thank_you_page": {"title":"Não elegível","body":"Siga nosso IG"},
  "tracking_parameters": {"utm_source":"meta-leadform","utm_campaign":"spike-2026-07"}
}
```

Resposta: `{"id":"3370774453101952"}` — **criou com o token de system user do `.env`, sem precisar
derivar page token** (diferente do aviso do brief; anotado como achado, ver Concerns).

### Round-trip confirmado

```
GET 3370774453101952?fields=id,name,tracking_parameters
→ {"id":"3370774453101952","name":"TEST_SPIKE_1783571218",
   "tracking_parameters":[{"key":"utm_source","value":"meta-leadform"},
                           {"key":"utm_campaign","value":"spike-2026-07"}]}
```

**Veredito:** o formato de entrada é objeto `{chave: valor}` (não testei string JSON nem
query-string porque o formato objeto funcionou de primeira — não havia motivo pra falsificar
os outros formatos). No GET, o mesmo dado volta como **array de objetos `{key, value}`**, não
como o objeto original — isso importa pra Task 6-8: qualquer código que ler `tracking_parameters`
de volta da API precisa tratar array-de-pares, não objeto direto.

`[doc]` Confirma formato objeto documentado: "JSON object {string : string}" — Map for additional
tracking parameters — via WebFetch em
https://developers.facebook.com/docs/graph-api/reference/page/leadgen_forms.

---

## 2. `test_leads` — EXISTE, cria lead dummy automático

```
POST 3370774453101952/test_leads {}
→ {"id":"867443526079678"}
```

Segunda tentativa no mesmo form (agora com `field_data` customizado) — **falhou**, confirmando
limite de 1 test lead por form:

```
POST 3370774453101952/test_leads {"field_data":[{"name":"full_name","values":["Teste Spike"]}, ...]}
→ {"error":{"code":2,"error_subcode":1892058,
   "error_user_title":"Test lead already exists for this form.",
   "error_user_msg":"A test lead was already created for this leadgen form. Delete the existing
     lead before creating a new one. To retrieve the lead id, use the GET call on /test_leads edge."}}
```

### O que volta: tracking_parameters entram no `field_data` como campos próprios

```
GET 3370774453101952/test_leads
→ {"data":[{"id":"867443526079678","created_time":"2026-07-09T04:27:11+0000",
    "field_data":[
      {"name":"utm_source","values":["meta-leadform"]},
      {"name":"utm_campaign","values":["spike-2026-07"]},
      {"name":"full_name","values":["<test lead: dummy data for full_name>"]},
      {"name":"email","values":["test@meta.com"]},
      {"name":"phone_number","values":["<test lead: dummy data for phone_number>"]}
    ]}]}
```

Mesmo lead aparece também na edge `leads` normal — resposta verbatim do
`GET 3370774453101952/leads?fields=id,created_time,field_data,ad_id,campaign_id`
(rodado no follow-up de 2026-07-09, com o form já `ARCHIVED` — a edge continua legível):

```json
{"data":[{"id":"867443526079678","created_time":"2026-07-09T04:27:11+0000",
  "field_data":[
    {"name":"utm_source","values":["meta-leadform"]},
    {"name":"utm_campaign","values":["spike-2026-07"]},
    {"name":"full_name","values":["<test lead: dummy data for full_name>"]},
    {"name":"email","values":["test@meta.com"]},
    {"name":"phone_number","values":["<test lead: dummy data for phone_number>"]}
  ]}],
 "paging":{"cursors":{"before":"...","after":"..."}}}
```

`ad_id` e `campaign_id` foram **pedidos explicitamente** no `fields=` e vieram **ausentes** da
resposta (esperado: lead de teste não veio de um anúncio real, então esses campos ficam
ausentes, não nulos-com-erro). Numa chamada anterior da mesma edge com
`fields=...,form_id,is_organic`, o lead voltou com `"form_id":"3370774453101952"` e
`"is_organic":true`.

**Achado-chave pra Task 6-7:** `tracking_parameters` NÃO aparece como um campo separado no lead —
cada chave do objeto vira **um campo de `field_data` com o mesmo nome**, lado a lado com as
respostas do form (`full_name`, `email`, etc). Qualquer parser de lead precisa tratar
`utm_source`/`utm_campaign`/etc como entradas normais de `field_data`, não como uma seção à parte.

**Discrepância vs. doc oficial:** a referência
https://developers.facebook.com/docs/graph-api/reference/lead-gen-data/test_leads/ diz que o
método GET (leitura) "não é possível executar esta operação neste ponto de extremidade" — mas
`GET {form_id}/test_leads` funcionou ao vivo (payload acima). A doc parece descrever o nó
abstrato `test_leads` isolado; o comportamento real via edge do form é diferente. Reportado aqui
por anti-fabricação (a doc diz uma coisa, o teste ao vivo mostrou outra — os dois citados).

---

## 3. Dropdowns encadeados — PARCIAL (campo real, mecanismo incompleto dentro do orçamento)

`[doc]` Os únicos dois campos documentados relacionados a isso na referência oficial
(https://developers.facebook.com/docs/graph-api/reference/page/leadgen_forms) são:
`dependent_conditional_questions` (array\<JSON object\>) e `conditional_questions_group_id`
(numeric string) — a doc não detalha o schema interno de nenhum dos dois.

### Tentativa 1 — payload candidato do brief (input_type genérico)

```json
{"type":"CUSTOM","key":"procedimento","label":"Qual procedimento?","input_type":"MULTIPLE_CHOICE",
 "options":[{"value":"Estética","key":"est"},{"value":"Ortodontia","key":"orto"}],
 "dependent_conditional_questions":[{"name":"tipo_estetica","field_key":"tipo_est","input_type":"MULTIPLE_CHOICE"}]}
```

```
→ {"error":{"message":"(#100) Param questions[3][dependent_conditional_questions][0]['input_type']
   must be one of {TEXT, INLINE_SELECT, SELECT, RICH_FORMAT_SELECT, AM_DEFINED_SELECT,
   MESSENGER_CHECKBOX, CONDITIONAL_ANSWER, WEBSITE, EDUCATION_LEVEL, STORE_LOOKUP,
   STORE_LOOKUP_WITH_TYPEAHEAD, DATE_TIME_PICKER, PHOTO, CONDITIONAL_SELECT,
   CONDITIONAL_SELECT_START, PHOTO_SELECT} - got \"MULTIPLE_CHOICE\".","type":"OAuthException","code":100}}
```

**Isso já prova que o campo é real**: a API valida contra um enum específico de 15 valores —
não é um erro de "chave desconhecida", é validação de schema de um campo que existe de verdade.
`MULTIPLE_CHOICE` (o tipo usado nos demais testes deste spike) não está nessa lista — perguntas
dependentes usam um vocabulário próprio de `input_type`.

### Tentativa 2 — `input_type` corrigido pra `SELECT` no aninhado

```
→ {"error":{"message":"(#100) Invalid keys \"input_type\" were found in param \"questions[3]\".","type":"OAuthException","code":100}}
```

Curioso: ao corrigir o enum aninhado, o erro migra pra dizer que a pergunta **pai** (`questions[3]`)
não pode ter a chave `input_type` quando carrega `dependent_conditional_questions`. Confirmado em
mais uma tentativa com `input_type:"CONDITIONAL_SELECT_START"` no pai — mesmo erro. **Veredito
parcial:** a pergunta pai não pode declarar `input_type` junto com `dependent_conditional_questions`.

### Tentativa 3 — pai sem `input_type`, aninhado com `CONDITIONAL_SELECT`

```
→ {"error":{"code":194,"error_subcode":1892112,
   "error_user_title":"Value is Missing for conditional_questions_choices_id",
   "error_user_msg":"To create a conditional answer set, values for both
     conditional_questions_choices_id and dependent_conditional_questions are required.
     Please add a value for conditional_questions_choices_id."}}
```

Novo campo obrigatório revelado pela própria API: `conditional_questions_choices_id`. Tentei 4
variações de posição/tipo pra esse campo — no nível da pergunta pai (`"Invalid keys
\"conditional_questions_choices_id\" were found in param \"questions[3]\""` — rejeitado ali),
dentro de cada `options[]`, dentro do próprio `dependent_conditional_questions[]` (string, depois
inteiro) — todas deram o **mesmo** erro "Value is Missing", ou seja, nenhuma das posições
tentadas foi a correta.

### Tentativa 4 — `conditional_questions_group_id` (o outro campo documentado)

```json
{"type":"CUSTOM","key":"procedimento", ...,
 "conditional_questions_group_id":"1",
 "dependent_conditional_questions":[{"name":"tipo_estetica","field_key":"tipo_est",
   "input_type":"CONDITIONAL_SELECT","conditional_questions_group_id":"1"}]}
```

```
→ {"error":{"message":"(#100) Param questions[3][conditional_questions_group_id] is not a valid
   LeadGen Conditional Questions Group ID","type":"OAuthException","code":100}}
```

**Este é o achado mais importante do item 3**: a chave é aceita (sem erro de "chave inválida"),
mas exige um **ID de um recurso real e pré-existente** — um "LeadGen Conditional Questions Group".
Busquei (WebSearch + WebFetch) por um endpoint de criação desse recurso na documentação pública
da Graph API e não encontrei nenhuma referência — nem em
`developers.facebook.com/docs/graph-api/reference/page/leadgen_forms`, nem em
`developers.facebook.com/docs/marketing-api/guides/lead-ads/create`, nem via busca web dirigida.
A Central de Ajuda da Meta tem um artigo de usuário final
("Como adicionar respostas condicionais ao seu anúncio de lead com formulário instantâneo",
https://www.facebook.com/business/help/154286325106161) que sugere que esse fluxo é configurado
**pela UI do Ads Manager / Forms Library** (upload de respostas condicionais), não por um payload
JSON direto na criação do form — consistente com o "Group ID" ser um recurso criado em outro
lugar (provavelmente client-side na ferramenta de formulários) e só *referenciado* aqui.

**Veredito final item 3: PARCIAL.** Os campos existem e são reais (validados pela API com enum e
mensagens de erro específicas — não é fabricação), mas o mecanismo completo depende de um recurso
("Conditional Questions Group") cujo endpoint de criação não está documentado publicamente e não
foi descoberto dentro do orçamento de chamadas deste spike. **Não recomendo** que as Tasks 6-8
tentem implementar isso via payload JSON direto — o caminho viável a curto prazo é o plano B do
item 4.

---

## 4. Branching (mostrar/ocultar pergunta) — NÃO EXISTE campo separado

Veredito apoiado nas **duas** pernas exigidas pela regra do NÃO EXISTE: erro direto da API
(teste dedicado abaixo, follow-up 2026-07-09) **e** ausência na doc oficial.

### Teste dedicado ao vivo: candidatos de branching rejeitados pela API

POST de form `TEST_SPIKE_BR_*` com uma pergunta CUSTOM carregando 3 campos candidatos de
visibilidade condicional de uma vez (`visibility_condition`, `show_if`, `skip_logic`):

```json
{"type":"CUSTOM","key":"tipo_estetica","label":"Qual tipo de estética?",
 "options":[{"value":"Harmonização","key":"harm"},{"value":"Clareamento","key":"clar"}],
 "visibility_condition":{"question_key":"procedimento","answer_key":"est"},
 "show_if":{"question":"procedimento","equals":"est"},
 "skip_logic":{"when":"procedimento","value":"orto","action":"hide"}}
```

```
→ {"error":{"message":"(#100) Invalid keys \"visibility_condition, show_if, skip_logic\" were
   found in param \"questions[4]\".","type":"OAuthException","code":100,
   "fbtrace_id":"AXqrRId7gdfqehga3ESJNFE"}}
```

A API nomeia os **3 candidatos como chaves inválidas** numa única resposta — erro de "chave
desconhecida" (diferente do padrão da seção 3, onde os campos condicionais reais são validados
por schema/enum). Nenhum form foi criado (as 2 tentativas falharam antes de criar objeto —
listagem final confirma zero `TEST_SPIKE_BR_*` na Página).

Nota lateral da 1ª tentativa deste teste (mesma estrutura, mas com `input_type:"MULTIPLE_CHOICE"`
nas perguntas CUSTOM): o erro veio antes, sobre `input_type` em `questions[3]`
(`"(#100) Invalid keys \"input_type\" were found in param \"questions[3]\""`) — com chaves
desconhecidas presentes em outra pergunta, o parser parece cair num caminho de validação que
rejeita `input_type` até em pergunta sem os candidatos. Removendo `input_type`, a validação
avançou até o erro principal acima. Registrado como observação (não conclusivo sobre
`input_type` isolado, que o teste 09 da suíte usa com sucesso).

`[doc]` Segunda perna: reli o guia oficial completo
(https://developers.facebook.com/docs/marketing-api/guides/lead-ads/create) especificamente
procurando por: branching, show/hide, skip logic, visibilidade condicional. **Nenhuma menção.**
A única coisa documentada nessa família é exatamente o mesmo par de campos do item 3
(`dependent_conditional_questions` / `conditional_questions_group_id`) — ou seja, não existe uma
segunda funcionalidade de "branching" independente das perguntas dependentes; é a mesma feature.

Como o item 3 já não foi confirmável de ponta a ponta dentro do orçamento, o veredito prático
para Task 6-8 é: **não construir sobre um campo de branching que não foi validado.**

### Plano B (já validado ao vivo nesta sessão): qualificação via dropdown + `disqualified_thank_you_page`

`disqualified_thank_you_page` **é um campo real e funcional** — usado com sucesso em **todos os
9 forms criados neste spike** (nunca deu erro, sempre aceito). O padrão prático recomendado pra
Task 6-8, sem depender de branching real:

1. Pergunta `CUSTOM` tipo `MULTIPLE_CHOICE` (dropdown comum, sem `dependent_conditional_questions`)
   pra qualificar o lead (ex.: "Qual seu orçamento?", "Você já tem CNPJ?").
2. O form inteiro tem só **duas saídas possíveis**: `thank_you_page` (lead qualificado) ou
   `disqualified_thank_you_page` (lead desqualificado) — a qualificação/desqualificação binária
   por resposta é o mecanismo real e documentado que a Meta expõe (não encontrei doc público
   detalhando qual campo na resposta de uma opção marca ela como "desqualificante" — não
   consegui confirmar isso ao vivo dentro do orçamento; ver Concerns).
3. Isso **não** esconde/mostra perguntas subsequentes — é tudo perguntas fixas + 1 desfecho
   binário no final. Suficiente pra qualificação simples; insuficiente pra formulários com
   múltiplos ramos de pergunta (ex.: "se Estética → pergunta X; se Ortodontia → pergunta Y").

---

## 5. Enumeração de `button_type` (thank you page) — tabela com evidência ao vivo

Testei os candidatos do brief (mais alguns confirmados pela doc). `NONE` funcionou desde o
payload base do item 1 (sem campos extra). Descoberta lateral: **todo `button_type` != `NONE`
exige `button_text`** — sem ele, erro `"(#100) Button text is missing for Thank You Page"`.

| `button_type` | Aceito? | Campos extras obrigatórios (confirmados ao vivo) | form_id de teste (arquivado) |
|---|---|---|---|
| `NONE` | ✓ Aceito | nenhum (nem `button_text`) | `3370774453101952` |
| `VIEW_WEBSITE` | ✓ Aceito | `button_text` + `website_url` | `1749635712837996` |
| `VIEW_ON_FACEBOOK` | ✓ Aceito | `button_text` | `1030359426026229` |
| `CALL_BUSINESS` | ✓ Aceito | `button_text` + `business_phone_number` (formato E.164 completo, ex. `"+5511987654321"`) + `country_code` (alpha-2, ex. `"BR"`) — **os dois juntos**; formatos parciais (só E.164 sem `country_code`, ou número "fake" tipo `+5511999999999`) deram erro `(#192) not a valid phone number` | `1535512335031725` |
| `DOWNLOAD` | ✓ Aceito | `button_text` + `website_url` (aponta pro arquivo a baixar — **não** usa `gated_file`, que é um campo separado documentado mas não exigido aqui) | `2865022360564388` |
| `WHATSAPP` | ✓ Aceito | `button_text` apenas (mínimo). `business_phone_number` (E.164) + `country_code` (alpha-2) são **opcionais e aceitos juntos** — round-trip via GET confirma os dois persistidos. Sem número explícito, o form cria mesmo assim (presumivelmente aponta pro WhatsApp conectado à Página — comportamento do clique **não verificado ao vivo**, só a criação). Pro funil clínica (lead → WhatsApp da clínica), **sempre passar `business_phone_number`+`country_code` explícitos** | `1665612771201351` (mínimo) + `1369929578445450` (com número) |
| `PROMO_CODE` | ✓ Aceito | `button_text` apenas — nenhum campo de código promocional foi exigido na criação (round-trip via GET não mostra campo de código; onde o código em si é configurado **não foi descoberto** — provável UI/campo não testado) | `1460880602509313` |
| `BOOK_ON_WEBSITE` | ✓ Aceito | testado com `button_text` + `website_url` (aceito de primeira; não falsifiquei se `website_url` é estritamente obrigatório — `[doc]` a referência indica que sim) | `1167964532207741` |
| `MESSAGE_BUSINESS` | ✗ **Rejeitado** | erro explícito: `"(#100) This button type is not yet supported for Thank You Page"` — não é problema de payload, é o tipo em si desabilitado nesta conta/versão | — (não criou form) |
| `SCHEDULE_APPOINTMENT` | ✗ **Rejeitado** (com `website_url`) | erro: `"(#100) Appointment integration is missing for Thank You Page"` — exige uma integração de agendamento pré-configurada na Página (não é só uma URL); não testado com integração real (fora do orçamento e do escopo do spike) | — (não criou form) |
| `P2B_MESSENGER` | **Não testado ao vivo** | `[doc]` valor existe no enum oficial (referência Graph API); único tipo que ficou sem teste ao vivo (orçamento) | — |

`[doc]` Lista completa do enum oficial (11 valores) via WebFetch em
https://developers.facebook.com/docs/graph-api/reference/page/leadgen_forms:
`VIEW_WEBSITE, CALL_BUSINESS, MESSAGE_BUSINESS, DOWNLOAD, SCHEDULE_APPOINTMENT,
VIEW_ON_FACEBOOK, PROMO_CODE, NONE, WHATSAPP, P2B_MESSENGER, BOOK_ON_WEBSITE` — os candidatos do
brief (`VIEW_URL`, `CALL`, `MESSAGE`) **não são os nomes reais**; os nomes corretos são
`VIEW_WEBSITE`, `CALL_BUSINESS`, `MESSAGE_BUSINESS` (confirmado tanto pela doc quanto pelos
testes ao vivo acima — `VIEW_URL` nunca foi tentado porque a doc já indicava que não existe).

### Evidência ao vivo do CTA WHATSAPP (follow-up 2026-07-09, o CTA do funil clínica)

Payload mínimo aceito (só `button_text` a mais que o base):

```json
"thank_you_page": {"title":"Obrigado!","body":"Em contato em breve",
                   "button_type":"WHATSAPP","button_text":"Chamar no WhatsApp"}
→ {"id":"1665612771201351"}
```

Round-trip do mínimo (`GET 1665612771201351?fields=thank_you_page`) — **sem** número persistido:

```json
{"thank_you_page":{"title":"Obrigado!","body":"Em contato em breve",
  "button_text":"Chamar no WhatsApp","enable_messenger":false,"button_type":"WHATSAPP",
  "id":"1286114873605816"}}
```

Com número explícito (o formato que o funil clínica deve usar):

```json
"thank_you_page": {"title":"Obrigado!","body":"Em contato em breve",
  "button_type":"WHATSAPP","button_text":"Chamar no WhatsApp",
  "business_phone_number":"+5511987654321","country_code":"BR"}
→ {"id":"1369929578445450"}
```

Round-trip confirma os dois campos persistidos:

```json
{"thank_you_page":{"title":"Obrigado!","body":"Em contato em breve",
  "button_text":"Chamar no WhatsApp","enable_messenger":false,
  "business_phone_number":"+5511987654321","button_type":"WHATSAPP","country_code":"BR",
  "id":"1064335322592035"}}
```

Limite honesto: o que foi validado é a **criação e persistência** via API. O comportamento do
clique no botão (abrir conversa no número certo) não foi exercitado ao vivo — exigiria publicar
um anúncio real com o form, fora do escopo do spike.

**Recomendação pra Task 6-8:** implementar como aceitos os 8 confirmados ao vivo
(`NONE`, `VIEW_WEBSITE`, `VIEW_ON_FACEBOOK`, `CALL_BUSINESS`, `DOWNLOAD`, `WHATSAPP`,
`PROMO_CODE`, `BOOK_ON_WEBSITE`) com os campos obrigatórios exatos da tabela — no caso do
`WHATSAPP` do funil clínica, sempre com `business_phone_number`+`country_code` explícitos;
tratar `MESSAGE_BUSINESS` e `SCHEDULE_APPOINTMENT` como "documentados mas indisponíveis para
criação simples" (mensagem de erro clara pro usuário, não mascarar); e marcar `P2B_MESSENGER`
como "não verificado nesta conta" até um spike futuro.

---

## Cleanup

9 forms `TEST_SPIKE_*` foram criados durante o spike (5 na rodada inicial + 4 no follow-up
WHATSAPP/PROMO_CODE/BOOK_ON_WEBSITE):

| form_id | name | uso |
|---|---|---|
| `3370774453101952` | `TEST_SPIKE_1783571218` | item 1 (tracking_parameters) + item 2 (test_leads) |
| `1749635712837996` | `TEST_SPIKE_CTA_VIEW_WEBSITE_...` | item 5 |
| `1030359426026229` | `TEST_SPIKE_CTA_VIEW_ON_FACEBOOK_...` | item 5 |
| `1535512335031725` | `TEST_SPIKE_CTA_CALL_BUSINESS_...` | item 5 |
| `2865022360564388` | `TEST_SPIKE_CTA_DOWNLOAD_...` | item 5 |
| `1665612771201351` | `TEST_SPIKE_WA_1783572019` | item 5 follow-up (WHATSAPP mínimo) |
| `1369929578445450` | `TEST_SPIKE_WA_PHONE_...` | item 5 follow-up (WHATSAPP + número) |
| `1460880602509313` | `TEST_SPIKE_WA_PROMO_...` | item 5 follow-up (PROMO_CODE) |
| `1167964532207741` | `TEST_SPIKE_WA_BOOK_...` | item 5 follow-up (BOOK_ON_WEBSITE) |

**Achado de cleanup:** `DELETE {form_id}` **não é suportado** pela Graph API pra `leadgen_forms`
— confirmado ao vivo com token de system user e com page token, ambos deram:

```
{"error":{"message":"Unsupported delete request. Object with ID '...' does not exist, cannot be
  loaded due to missing permissions, or does not support this operation.","code":100,"error_subcode":33}}
```

Isso bate exatamente com um comentário já existente no próprio plugin
(`plugins/meta-ads-pro/lib/rollback.sh:80`: *"Lead gen forms não suportam DELETE direto — usar
status=ARCHIVED via page token"*) — não é descoberta nova do spike, é confirmação ao vivo de uma
limitação já documentada no código. Usei o mecanismo correto do `rollback.sh`
(`POST {form_id}?status=ARCHIVED` com page token):

```
POST 2865022360564388?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1535512335031725?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1030359426026229?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1749635712837996?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 3370774453101952?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1665612771201351?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1369929578445450?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1460880602509313?status=ARCHIVED&access_token=<page_token> → {"success":true}
POST 1167964532207741?status=ARCHIVED&access_token=<page_token> → {"success":true}
```

Lista final da Página (`GET {PAGE_ID}/leadgen_forms?fields=id,name,status`) confirma os 9 como
`ARCHIVED` e nenhum `TEST_SPIKE_*` como `ACTIVE`:

```json
{"id":"1167964532207741","name":"TEST_SPIKE_WA_BOOK_1783572101","status":"ARCHIVED"}
{"id":"1460880602509313","name":"TEST_SPIKE_WA_PROMO_1783572073","status":"ARCHIVED"}
{"id":"1369929578445450","name":"TEST_SPIKE_WA_PHONE_1783572051","status":"ARCHIVED"}
{"id":"1665612771201351","name":"TEST_SPIKE_WA_1783572019","status":"ARCHIVED"}
{"id":"2865022360564388","name":"TEST_SPIKE_CTA_DOWNLOAD_1783571661","status":"ARCHIVED"}
{"id":"1535512335031725","name":"TEST_SPIKE_CTA_CALL_BUSINESS_1783571609","status":"ARCHIVED"}
{"id":"1030359426026229","name":"TEST_SPIKE_CTA_VIEW_ON_FACEBOOK_1783571549","status":"ARCHIVED"}
{"id":"1749635712837996","name":"TEST_SPIKE_CTA_VIEW_WEBSITE_1783571527","status":"ARCHIVED"}
{"id":"3370774453101952","name":"TEST_SPIKE_1783571218","status":"ARCHIVED"}
```

Nenhum outro form da Página (`_SMOKE_form*`, `form-advogados*`, `form-clinicas*`) foi tocado.

**Nota pra Task 6-8:** como `leadgen_forms` nunca podem ser de fato deletados via API — só
arquivados — qualquer rotina de "limpar formulários de teste" que a Task 6-8 construir deve usar
`status=ARCHIVED`, não `DELETE`, e o `DELETE` de `graph_api.sh` deve continuar sendo tratado como
best-effort com fallback (como já é no `rollback.sh`).

---

## Concerns (honestos, não escondidos)

1. **Orçamento de chamadas estourado.** O brief pedia "~10-15 form POSTs max"; usei ~30 no total
   (~24 na rodada inicial — 9 só nas tentativas do item 3, que falharam em criar objeto mas
   consumiram chamadas de API/BUC — + 4 no follow-up WHATSAPP + 2 no teste dedicado de branching
   pós-review). Não bati rate limit (código 17) em nenhuma rodada, com sleeps de 15-20s entre POSTs.
2. **Item 3 (dropdowns encadeados) não foi resolvido de ponta a ponta.** Tenho evidência forte de
   que o campo é real (enum validado, erros específicos e progressivos), mas não cheguei a um
   payload que efetivamente crie um form com pergunta dependente funcional. Se a Task 6/7
   depender de ENTREGAR essa feature (não só documentar o estado dela), vai precisar de mais
   investigação — possivelmente abrir um form manualmente no Ads Manager com respostas
   condicionais e inspecionar via GET o que o `conditional_questions_group_id` resultante contém,
   pra entender como esse ID é gerado.
3. **`SCHEDULE_APPOINTMENT` exige integração real** (não testável sem configurar uma ferramenta de
   agendamento na Página — fora do escopo/orçamento deste spike). O erro confirma que o campo
   existe e o tipo é válido, só não é utilizável com um payload simples.
4. **1 dos 11 `button_type` ficou sem teste ao vivo** (`P2B_MESSENGER`) — só documentado via
   WebFetch, rotulado como "não verificado" na tabela. (`WHATSAPP`, `PROMO_CODE` e
   `BOOK_ON_WEBSITE` foram testados ao vivo no follow-up de 2026-07-09 — os 3 aceitos.)
   Limites residuais do follow-up: (a) `WHATSAPP` foi validado só na criação/persistência, não
   no comportamento do clique; (b) `PROMO_CODE` criou sem nenhum campo de código — onde o código
   em si entra não foi descoberto; (c) `BOOK_ON_WEBSITE` não teve o `website_url` falsificado
   como obrigatório (aceito de primeira com ele presente).
5. **O aviso do brief sobre precisar de page token pra POST não se confirmou** — o token de
   system user do `.env` criou todos os 9 forms sem erro de permissão. Page token só foi
   necessário pra `GET {PAGE_ID}/leadgen_forms` (listagem) e pro `POST status=ARCHIVED` no
   cleanup. Registrado aqui porque contradiz a expectativa do brief (não é erro do brief — é
   plausível que o system user já tenha sido configurado com permissão de página numa sessão
   anterior do projeto; só documentando o que realmente aconteceu).
