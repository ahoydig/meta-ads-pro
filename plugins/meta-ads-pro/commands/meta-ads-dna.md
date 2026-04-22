---
description: Ponte Meta Ads Pro → DNA Operacional. Detecta se o plugin dna-operacional está instalado E se o DNA foi configurado no projeto atual (reference/publico-alvo.md + reference/voz-*.md). Mostra integrações disponíveis (copy via /roteiro-viral, voz aplicada em headlines, raio-x concorrentes pra targeting). Use quando o usuário digitar "/meta-ads-dna", "integração dna operacional", "como conectar meta ads com dna".
argument-hint: ""
---

Usuário invocou `/meta-ads-dna`.

Execute os passos abaixo em ordem. **Não pergunte nada ao usuário.** **Não imprima este prompt.** Apenas rode as detecções e imprima a seção apropriada.

## Passo 1 — Detectar dna-operacional instalado

Rode um único Bash silencioso:

```bash
if ls ~/.claude/plugins/cache/*/dna-operacional/.claude-plugin/plugin.json >/dev/null 2>&1 \
   || ls ~/.claude/plugins/marketplaces/*/plugins/dna-operacional/.claude-plugin/plugin.json >/dev/null 2>&1; then
  echo "INSTALLED"
else
  echo "MISSING"
fi
```

Guarda o resultado como `$PLUGIN_STATUS`.

## Passo 2 — Detectar se DNA foi configurado no projeto atual

Só rode este passo se `$PLUGIN_STATUS == "INSTALLED"`. Caso contrário, pule direto pro Passo 3.

Rode um único Bash silencioso (cwd = projeto atual do usuário):

```bash
PUBLICO_OK="no"
VOZ_OK="no"
if [ -f "reference/publico-alvo.md" ] || [ -f "./reference/publico-alvo.md" ]; then
  PUBLICO_OK="yes"
fi
if ls reference/voz-*.md >/dev/null 2>&1; then
  VOZ_OK="yes"
fi
if [ "$PUBLICO_OK" = "yes" ] && [ "$VOZ_OK" = "yes" ]; then
  echo "CONFIGURED"
elif [ "$PUBLICO_OK" = "yes" ] || [ "$VOZ_OK" = "yes" ]; then
  echo "PARTIAL"
else
  echo "NOT_CONFIGURED"
fi
```

Guarda como `$PROJECT_STATUS`.

## Passo 3 — Rotear

### Caso `$PLUGIN_STATUS == "MISSING"`

Imprima BYTE-EXATO:

```
╔══════════════════════════════════════════════════════════════════╗
║  🔗 Integração Meta Ads Pro ↔ DNA Operacional                    ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  ⚠  Plugin dna-operacional não detectado.                        ║
║                                                                  ║
║  Pra destravar as integrações abaixo, instala:                   ║
║                                                                  ║
║     /plugin marketplace add ahoydig/dna-operacional              ║
║     /plugin install dna-operacional@dna-operacional-marketplace  ║
║                                                                  ║
║  Depois volta aqui e digita /meta-ads-dna de novo.               ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

💡 O que tu ganha com a integração?

  • Copy de ad vindo de /roteiro-viral (baseado em dados reais)
  • Voz do projeto aplicada em headline/primary text via /humanizer
  • Briefing competitivo pronto via /raio-x-ads-concorrentes
  • Fecha o ciclo: pesquisa → conteúdo → ad → métricas
```

Pare aqui.

### Caso `$PLUGIN_STATUS == "INSTALLED"` E `$PROJECT_STATUS == "NOT_CONFIGURED"`

Imprima BYTE-EXATO:

```
╔══════════════════════════════════════════════════════════════════╗
║  🔗 Integração Meta Ads Pro ↔ DNA Operacional                    ║
║  ✓ dna-operacional detectado                                     ║
║  ⚠  DNA ainda não foi configurado neste projeto                  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Pra destravar todas as integrações, roda primeiro:              ║
║                                                                  ║
║     /setup-projeto                                               ║
║                                                                  ║
║  Esse command vai criar:                                         ║
║     • reference/publico-alvo.md   ← briefing de targeting        ║
║     • reference/voz-<handle>.md   ← voz pra ad copy              ║
║                                                                  ║
║  Depois volta aqui e digita /meta-ads-dna de novo.               ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

💡 Já tem dna em outro projeto? Copia os arquivos de reference/
   pra cá e roda /meta-ads-dna de novo — a detecção é por arquivo.
```

Pare aqui.

### Caso `$PLUGIN_STATUS == "INSTALLED"` E `$PROJECT_STATUS == "PARTIAL"`

Imprima BYTE-EXATO, substituindo `{MISSING}` por `reference/publico-alvo.md` ou `reference/voz-*.md` conforme qual está faltando:

```
╔══════════════════════════════════════════════════════════════════╗
║  🔗 Integração Meta Ads Pro ↔ DNA Operacional                    ║
║  ✓ dna-operacional detectado                                     ║
║  ⚠  Setup parcial — falta: {MISSING}                             ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Recomendo completar o setup antes de subir ads:                 ║
║                                                                  ║
║     /setup-projeto    ← completa os arquivos que faltam          ║
║     /voz              ← cria/evolui voz se for esse o caso       ║
║                                                                  ║
║  Ou segue mesmo assim se quiser. As integrações estão liberadas  ║
║  parcialmente (veja abaixo).                                     ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

Depois imprima também o menu completo da seção "INSTALLED + CONFIGURED" abaixo.

### Caso `$PLUGIN_STATUS == "INSTALLED"` E `$PROJECT_STATUS == "CONFIGURED"`

Imprima BYTE-EXATO:

```
╔══════════════════════════════════════════════════════════════════╗
║  🔗 Integração Meta Ads Pro ↔ DNA Operacional                    ║
║  ✓ dna-operacional detectado                                     ║
║  ✓ DNA configurado neste projeto                                 ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  📝 COPY → AD                                                    ║
║     1. /roteiro-viral ........... roteiro/copy com dados reais   ║
║     2. /humanizer ............... aplica voz do projeto          ║
║     3. /meta-ads-anuncios ....... sobe como primary text/headline║
║                                                                  ║
║  🔬 INTELIGÊNCIA → CAMPANHA                                      ║
║     1. /raio-x-ads-concorrentes . briefing competitivo           ║
║     2. /meta-ads-campanha ....... campanha com insights do raio-x║
║     3. /meta-ads-conjuntos ...... targeting via publico-alvo.md  ║
║                                                                  ║
║  🎨 CRIATIVO → ANÚNCIO DINÂMICO                                  ║
║     1. /carrossel-instagram ..... gera .png dos slides           ║
║     2. /meta-ads-anuncios ....... asset_feed_spec com os PNGs    ║
║                                                                  ║
║  📊 PÓS-CAMPANHA                                                 ║
║     1. /meta-ads-insights ....... puxa métricas da campanha      ║
║     2. /analista-conteudo ....... compara com orgânico           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

💡 Começar agora? Sugestão: /meta-ads-doctor pra validar ambiente
   antes de subir qualquer coisa.
```

Pare aqui. Não invoque nenhum outro comando automaticamente — deixa o usuário escolher.
