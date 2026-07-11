# Plano v2: Fechamento v1.1 → Go-live do webhook → Piloto — meta-ads-pro

> Execução orquestrada (controller = Fable, analista/gates). Trabalho massivo em modelos inferiores: **haiku** = comando pronto/verificação mecânica; **sonnet** = browser/UI/diagnóstico/implementação. Fable NUNCA implementa — só adjudica evidência nos gates. **v2** = v1 + 21 correções dos loops de verificação adversarial (registro no fim).

**Estado de partida (2026-07-11):** PR #1 aberto e aprovado (`feat/v1.1-operacao-ahoy` @ `6f00036`). GHL destravado (PIT `meta-ads-pro-e2e` na subconta de teste `u0z5iy2DIlyMKk4zdMxu` "InfraJus Excluir", 4 scopes — evidência: ledger 2026-07-11; FB conectado via LeadConnector com a página Flávio Ahoy). Receiver local na VPS (127.0.0.1:8811), `META_APP_SECRET=PENDENTE_HUMANO`. Form `TEST_E2E_NATIVA_20260709_174845` ATIVO na página (verificado ao vivo pelo controller em 2026-07-11 — listagem no ledger; o report da T23 não existe porque o agente foi interrompido). Browser isolado logado em FluxiHub+FB. Conta Meta dev-tier.

## Cronograma por dias (BUC — teto empírico ~2 rodadas live/dia; contagem real de writes por fase)

- **Dia 1:** F0 (humano, paralelo) + F1 (~3-4 writes Meta; +1 se F1.0a precisar criar form novo).
- **Dia 2** (só com F0 completo): F2 (~3 writes) + F2.4 (monitoramento).
- **Dia 3:** F3 (~1 write).
- **Dia 4+:** F4 (janela própria, ~7-8 writes; nunca emendar no dia do F3).
- Se **F2.3** (prova crítica da cadeia pública) bater code 17: PARAR e retomar no dia seguinte — não degradar a evidência pra "seguir mesmo assim".

## Regras transversais

1. **Toda etapa tem "VALIDAR:" executável** — done só depois da validação passar. Falhou → diagnóstico (sonnet) antes de avançar; nunca "deve estar ok".
2. **Modelos:** o dispatch declara o modelo; subir de tier só com justificativa no ledger.
3. **BUC:** seguir o cronograma por dias acima; code 17 → anotar lacuna e seguir pro que não depende, nunca "aguardar em standing by".
4. **Browser isolado abre janelas visíveis** — combinar janela com o Flávio; agente interrompido NÃO é retomável (relançar do zero com estado verificado).
5. **Secrets:** token nunca em stdout/screenshot/`texto de comando` (transcript vaza!); captura só via arquivo; scripts de HMAC LEEM o secret do arquivo dentro do processo (nunca embutir o valor no comando); painel pedindo senha → parar. **O App Secret nunca deve ser colado no chat, em arquivo do repo, nem em comando de agente — o Flávio o leva DIRETO por SSH pro `.env` da VPS.**
6. **Anti-fabricação:** evidência verbatim em `docs/validacao/2026-07-e2e-infra-ahoy.md`.
7. **Confirmações do Flávio obrigatórias:** merge do PR (F3.2); TODA a F4 (etapa a etapa); ativação de campanha (F4.6, só ele); decisão de routing de produção (F2.0); disparo de teste do alerta no canal do time (F2.4 — mensagem visível a terceiros).
8. **Dois apps do Facebook distintos, independentes e coexistentes:** o caminho NATIVO usa o app da GoHighLevel (**LeadConnector**, conectado via Settings→Integrations da subconta); o caminho RECEIVER usa o **"Ahoy - APP"** (`995722365981851`), subscrito via `subscribed_apps` com page token. Conectar o LeadConnector NÃO subscreve o Ahoy - APP, e vice-versa.
9. **Qualidade da página:** se em qualquer ponto a página mostrar aviso de qualidade/elegibilidade de Lead Ads, pausar novas criações de form `TEST_` e investigar antes de continuar.

---

## F0 — Destravamentos humanos (2 itens, independentes; F1 roda em paralelo)

**F0.1 (HUMANO) Rota pública do tunnel.** ANTES de editar: **print/screenshot das regras atuais** do tunnel (backup visual — não há config.yml local). Painel CF: Zero Trust → Networks → Tunnels → `ahoy-hermes` → Public Hostname → Add: hostname `webhooks.ahoy.digital`, path `meta-leads*`, service `http://localhost:8811`, ACIMA da rota existente de webhooks. Alternativa: API token com `Cloudflare Tunnel:Edit` pro controller fazer via API — **ATENÇÃO: o PUT de configurations substitui a config INTEIRA do tunnel**; salvar o JSON do GET num arquivo como backup ANTES do PUT e rodar as mesmas 4 validações abaixo depois.
   VALIDAR (haiku, imediato): `curl -sS https://webhooks.ahoy.digital/meta-leads/health` → JSON com `received_total` (não 404/Access); `curl -sS -o /dev/null -w '%{http_code}' https://hermes.ahoy.digital` → vivo; `curl -sS -o /dev/null -w '%{http_code}' https://preview.ahoy.digital` → vivo (hostname irmão no mesmo tunnel); e um path do catch-all antigo de `webhooks.ahoy.digital` (ex.: `/` → resposta do gateway Hermes como antes). Qualquer um quebrado → restaurar pela foto do backup antes de qualquer outra coisa.

**F0.2 (HUMANO) App Secret.** Painel Meta app `995722365981851` → Configurações → Básico → App Secret "Mostrar" (senha) → **copiar DIRETO por SSH** pro `/opt/meta-leads/.env` (`META_APP_SECRET=`) → `systemctl restart meta-leads`. **NUNCA colar o secret no chat/repo/comando de agente** (regra 5).
   VALIDAR (haiku, imediato): na VPS — `grep -c '^META_APP_SECRET=PENDENTE_HUMANO' /opt/meta-leads/.env` → `0`; length do valor == 32 (checar via script que lê o arquivo, sem ecoar); serviço `active`; POST local assinado com secret ERRADO → 403; POST assinado com o CERTO → 200/500-semântico — usando script Python NA VPS que lê o secret do `.env` internamente e computa o HMAC (algoritmo: `docs/spikes/2026-07-webhook-leadgen.md` §6), sem o valor jamais aparecer em comando ou output.

---

## F1 — E2e caminho nativo + receiver local + CAPI (executável JÁ; 1 agente sonnet, gates Fable)

**F1.0 Pré-checagens executáveis** (haiku):
   a. Form existe? `GET {PAGE_ID}/leadgen_forms?fields=id,name,status` (page token) filtrando `TEST_E2E_NATIVA_20260709_174845` ATIVO. **Se não existir:** criar `TEST_E2E_NATIVA_<ts>` novo com o payload mínimo validado (thank you WHATSAPP + tracking_parameters) e seguir com ele.
   b. Scopes da PIT ok? `ghl_api GET /locations/${GHL_LOCATION_ID}` → 200 (não 401). Se 401: editar scopes na UI (Editar→Atualizar preserva o token; dropdown fecha com Escape) e revalidar.
   c. Test lead já existe no form? `GET {form_id}/leads` — se sim, REUSAR (limite 1/form); se não, F1.2 cria.
   d. Plumbing GHL da VPS real? `ssh root@5.78.224.81 "grep -c PENDENTE /opt/meta-leads/.env /opt/meta-leads/config.json"` → esperado: config.json `0`; `.env` `1` (o META_APP_SECRET do F0.2 — único placeholder legítimo até F0.2). **Já executado pelo controller em 2026-07-11: config.json OK (`108356564252733 → u0z5iy2DIlyMKk4zdMxu`), serviço active — plumbing confirmado real; re-checar mesmo assim no dia da execução.**

**F1.1 Mapear o form no GHL** (sonnet/browser). Subconta de teste → Settings → Integrations → Facebook Form Fields Mapping → localizar o form (refresh se preciso) → mapear full_name/email/phone_number → salvar.
   VALIDAR: descrição textual da tela pós-save mostrando o form como mapeado (+ screenshot descrito no doc).

**F1.2 Test lead** (1 write, se F1.0c não achou um). `POST {form_id}/test_leads`.
   VALIDAR: `GET {form_id}/leads?fields=field_data` → lead presente; conferir se `tracking_parameters` aparecem no `field_data` **deste test lead** (spike T2 provou para leads; test leads: registrar o observado — se NÃO vierem, anotar `[divergência test-lead]` no doc sem bloquear o fluxo, pois o veredito da nativa independe disso).

**F1.3 Veredito NATIVA** (mesmo agente). Aguardar até 3×60s; `ghl_api GET /contacts/?locationId=...&query=<email do lead>`.
   VALIDAR/GATE (Fable): contato com campos mapeados → NATIVA OK. Se nada após 3 tentativas: diagnóstico em árvore (form mapeado? conexão LeadConnector ativa? test lead dispara webhook do LeadConnector? — documentar cada checagem) ANTES de qualquer decisão.

**F1.4 Receiver local via assinatura** (mesmo agente, na VPS). **Checagem executável primeiro:** `grep -c '^META_APP_SECRET=PENDENTE_HUMANO' /opt/meta-leads/.env` → se `1`, assinar com o placeholder literal; se `0` (F0.2 já rodou), usar o script Python da validação de F0.2 (lê o secret do `.env` internamente — spike §6). Montar entrega fake com o `leadgen_id` REAL, POST em 127.0.0.1:8811.
   VALIDAR: HTTP 200; health `pushed`+1; contato upsertado no GHL SEM duplicar (conferir contagem por email).

**F1.5 CAPI test event** (browser + 1 write). Events Manager → pixel `947064561562400` → Testar eventos → código novo → `.env` local → test_04 do 19 isolado.
   VALIDAR: `events_received: 1` verbatim.

**F1.6 Cleanup + doc parcial.** Arquivar o form TEST_E2E (ARCHIVED, page token). Proteger forms legítimos: `Empresa Agêntica | Formulário` (visto ATIVO na listagem de 2026-07-11 — ledger), `form-advogados*`, `form-clinicas*`; `_SMOKE_form_20260421` = lixo pré-existente, anotar e não mexer. Contato de teste da subconta descartável: deletar ou anotar. Escrever `docs/validacao/2026-07-e2e-infra-ahoy.md`.
   VALIDAR/GATE (Fable): doc fiel às evidências → commit `docs(validacao): e2e parcial — nativa + receiver local + CAPI` + push na branch do PR.

---

## F2 — Go-live do webhook público (DEPENDE de F0.1 E F0.2; Dia 2; 1 agente sonnet)

**F2.0 DECISÃO (HUMANO) — routing de PRODUÇÃO da página Ahoy ANTES do Verify/Save.** No momento em que F2.1+F2.2 completarem, TODO lead real da página `108356564252733` (que tem forms legítimos ativos, ex. "Empresa Agêntica | Formulário") passa a ser entregue ao receiver e roteado pelo `config.json` — que hoje aponta pra subconta DESCARTÁVEL de teste. Lead real de prospect caindo em "InfraJus Excluir" = perda/embaraço. Decidir: (a) apontar o `config.json` da página Ahoy pra location REAL da Ahoy (ex.: "Ahoy Digital LTDA" `AbMjibgIceNTcqlFiXXH` ou "@flavioahoy" `1Cw89wIQw3S5pLCxwYL1`) com PIT de produção dessa location ANTES do go-live, OU (b) registrar explicitamente que leads reais cairão na location de teste durante a janela (e por quanto tempo). **Nota de duplicação:** a nativa (LeadConnector) entrega o mesmo lead na location mapeada DELA — com o receiver apontando pra outra, o mesmo lead vive em duas subcontas; decidir o par (nativa, receiver) conscientemente.
   VALIDAR: `config.json` reflete a decisão + restart + health up ANTES de F2.1.

**F2.1 Verify/Save no painel Meta** (browser). App → Webhooks → Page → Callback `https://webhooks.ahoy.digital/meta-leads` + verify token (lido do `.env` da VPS por script, sem ecoar) → "Verificar e salvar".
   VALIDAR: painel mostra callback salvo sem erro.

**F2.2 Assinar campo `leadgen` no nível do app** (pós-save; pendência do spike T4). Se a lista de campos aparecer: assinar `leadgen`. Documentar a tela real e ATUALIZAR o checklist §8 de `docs/spikes/2026-07-webhook-leadgen.md`.
   VALIDAR: campo listado como assinado (ou tela real documentada).

**F2.3 Test lead público ponta-a-ponta — isolando o caminho RECEIVER** (1-2 writes). Usar **form NOVO, NÃO mapeado no GHL** (isola o caminho: a nativa não pode criar o contato de um form sem mapping) → test lead → aguardar entrega REAL da Meta.
   VALIDAR/GATE (Fable): health `received_total`+1 E `pushed`+1 (assinatura real) E `last_status=pushed`; contato no GHL veio do receiver (source `meta-leadform-webhook` no contato + customFields do config.json). Cadeia Meta→tunnel→receiver→GHL PROVADA. Arquivar o form; doc atualizado + push.
   **ROLLBACK se falhar (executores NOMEADOS):** (0) interim IMEDIATO, executável pelo agente: `DELETE {PAGE_ID}/subscribed_apps` com page token — des-subscreve a página no Ahoy - APP e estanca as entregas NA ORIGEM (re-subscrever depois é 1 POST, validado no spike T4); (1) rota Cloudflare = Flávio no painel (ou controller, SE o caminho do API token de F0.1 tiver sido usado); (2) callback salvo no painel Meta = limpar o campo (browser isolado alcança); (3) reabrir só após validação local estilo F1.4 com o secret certo.

**F2.4 Monitoramento ANTES do piloto** (antecipado do F5.1 — sonnet). Cron diário na VPS: checar `/meta-leads/health` local; alertar no grupo do time (via Hermes/Barba) se `errors`/`no_config` crescer, `last_status` ficar `error:*` ou serviço down.
   VALIDAR: disparo de teste do alerta chega no canal do time. **F4 não começa sem isso ativo.**

---

## F3 — Merge + release (Dia 3; gates Fable; mecânico haiku)

**F3.1 Regressão final** (haiku):
   a. **Saúde LIVE** (a prova que importa): rodar `/meta-ads-crm status` (ou os checks 11-13 do `lib/preflight.sh` diretamente com o `.env` real carregado) → esperado ✓ GHL, ✓ receiver (público), ✓ subscrição. (`tests/04-doctor.sh` NÃO serve pra isso — testa o comportamento warn-não-bloqueia com env unset por design; rodá-lo apenas como regressão: 14/0.)
   b. `19-crm-capi.sh` completo → esperado 4 pass/0 skip. Se test_04 falhar por `CAPI_TEST_EVENT_CODE` expirado (expira por design): reobter no Events Manager (passo F1.5) e re-rodar antes de declarar regressão.
   c. `01-lint.sh` → 4/0.
   VALIDAR: contagens exatas; FAIL real → diagnóstico antes de F3.2.

**F3.2 Merge do PR #1 — CONFIRMAÇÃO DO FLÁVIO** (o marketplace serve da main). Merge commit normal (não squash).
   VALIDAR (haiku): main contém `6f00036`; `git log main -1` = merge.

**F3.3 Tag + instalação real** (sonnet): tag `v1.1.0` + push da tag; instalação limpa num diretório temp (`claude plugin marketplace add ...` + `install`, conforme README).
   VALIDAR: **encerrar a sessão Claude Code e abrir uma nova** (README linha 54 — commands só aparecem no startup) → `/meta-ads-crm`, `/meta-ads-boost`, `/meta-ads-news` disponíveis; versão 1.1.0.

---

## F4 — Piloto em cliente real (Dia 4+; TODA etapa = confirmação do Flávio; sonnet executa, Fable gate)

> Regra 8 vale dobrado aqui: F4.2 = app **LeadConnector** (nativa); F4.4 = app **Ahoy - APP** (receiver). São subscrições independentes — as duas são necessárias.

**F4.0 DECISÕES (HUMANO):** (a) qual clínica piloto + página FB + WhatsApp real do funil; (b) **workflow de recepção de lead está PUBLICADO** (não rascunho) na subconta? — sem workflow publicado, F4.5 não tem como validar.
**F4.1 PIT da subconta real** (browser; 4 scopes da Lição 11; **regra 5: captura só por arquivo, nunca no chat**). VALIDAR: `test_01` com env do cliente PASS.
**F4.2 Conexão LeadConnector da página do cliente** (OAuth — exige admin; se pedir credencial que não temos, o Flávio faz na tela). VALIDAR: card "Gerenciar" + página listada.
**F4.3 Receiver multi-cliente:** `config.json` += página do cliente → **restart em horário de baixo tráfego** (evitar janelas de campanhas ativas; registrar horário no doc; conferir no health pós-restart que `pushed`/`errors` não indicam entrega em voo perdida) → health up. VALIDAR: entrega de teste da página do cliente roteia pra location certa (F4.5 prova).
**F4.4 Subscrição leadgen da página do cliente no Ahoy - APP** (`subscribed_apps`, page token DELA). VALIDAR: GET lista `leadgen`.
**F4.5 Form real do funil + test lead — COM PROTEÇÃO DO CLIENTE:**
   a. **ANTES do test lead:** abrir o workflow do cliente e conferir se algum step notifica humano real (tarefa, SMS/WhatsApp/e-mail interno). Se sim: avisar o responsável do cliente que um lead de TESTE chega em horário combinado, OU pausar temporariamente só o step de notificação. Documentar a checagem.
   b. Form real (tracking_parameters + qualificador + WhatsApp CTA com número do cliente) → mapear no GHL → test lead.
   VALIDAR/GATE (Fable): contato na subconta REAL com UTMs; workflow disparou conforme combinado; reativar step pausado (se pausado).
**F4.6 Campanha real PAUSED → ativação:** usar EXCLUSIVAMENTE o flow `/meta-ads-campanha`→conjuntos→anúncios do plugin (PAUSED por padrão garantido pelo flow — nunca chamada manual à Graph API) → revisão do Flávio no Ads Manager → **ativação só pelo Flávio**.
   GATE final (Fable): funil respirou com lead de teste ANTES de budget real; doc `docs/validacao/2026-07-piloto-<cliente>.md`.

---

## F5 — Operação contínua (pós-piloto; sonnet)

**F5.1 — movido pra F2.4** (antes do piloto). Aqui: revisar thresholds do alerta com dados reais da 1ª semana.
**F5.2 Rotina mensal `/meta-ads-news`** (lembrete/cron). VALIDAR: 1 execução real registrada.
**F5.3 Backlog (não bloqueia):** fila local no receiver (janela de retry da Meta); Advanced Access do app quando houver página de cliente fora do BM Ahoy; dedupe do upsert GHL sob entrega duplicada — comportamento real ainda `[não verificado]` (relevante pro risco do restart, F4.3); **known gap do monitor (F2.4): o alerta roda na MESMA VPS que monitora e sai pelo MESMO Hermes — VPS down = monitor mudo; mitigação futura: healthcheck externo (ex.: cron no Mac ou serviço de uptime).**

---

## Registro de verificação do plano (loops)

- **v1 (2026-07-11):** rascunho do controller (Fable).
- **Loop 1 (2026-07-11):** 2 verificadores adversariais (sonnet) em paralelo. Lente executabilidade: APROVADO COM CORREÇÕES (2 Critical: evidência do form TEST_E2E ausente em arquivo → F1.0a + registro no ledger; F3.1 media comportamento da suíte, não saúde live → F3.1a. 7 Important, 2 Minor). Lente risco/produção: APROVADO COM CORREÇÕES (2 Critical: test lead sem checagem do workflow do cliente → F4.5a; go-live sem monitoramento → F2.4 antecipado. 5 Important, 3 Minor). Adjudicação (Fable): 21/21 findings aceitos, todos incorporados nesta v2.
- **Loop 2 (2026-07-11):** mesmas lentes sobre a v2. Executabilidade: 10/11 INCORPORADO + 1 PARCIAL (âncora nominal dos forms — resolvido: listagem nominal gravada no ledger) + 1 Important novo (F1.0d, plumbing VPS — adicionado E executado pelo controller: config.json real, único PENDENTE = App Secret/F0.2) + 1 Minor (aritmética de writes — corrigida). Risco: 10/10 INCORPORADO + 1 Critical novo (routing de produção da página Ahoy no go-live → **F2.0** criado) + 1 Important (executores do rollback F2.3 nomeados + interim des-subscrição) + 3 Minors (regra 7 ampliada; backup do JSON no caminho API de F0.1; known gap do monitor em F5.3). Adjudicação (Fable): 100% aceitos, incorporados nesta **v2.1**. Ambas as lentes: sem necessidade de loop 3 estrutural — correções pontuais, plano CONGELADO como v2.1.
