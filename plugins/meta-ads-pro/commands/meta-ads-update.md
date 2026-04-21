---
description: "Atualiza o plugin meta-ads-pro pra versão mais recente — git fetch + pull + install.sh, mostra CHANGELOG da versão nova. Executar do diretório raiz do plugin."
---

Uso:

```
/meta-ads-update
```

## Fluxo

1. **Valida que está no repo do plugin.** Confirma que `$PWD` contém
   `.claude-plugin/` e `lib/graph_api.sh`. Se não, erro claro:

   ```
   ✗ meta-ads-update precisa rodar no diretório do plugin
     (onde lib/graph_api.sh vive). PWD atual: $PWD
   ```

2. **Guarda versão atual.** Lê primeira linha do `CHANGELOG.md` (ou `git describe --tags`)
   pra comparar depois.

3. **Pull atualizações.**

   ```bash
   git fetch --tags --prune
   git pull --ff-only || {
     echo "✗ git pull falhou (merge conflict ou branch local divergente)"
     echo "  → resolve manual com 'git status' antes de tentar de novo"
     exit 1
   }
   ```

   `--ff-only` protege contra merges acidentais no plugin dir.

4. **Roda installer.**

   ```bash
   if [[ -f ./install.sh ]]; then
     ./install.sh
   else
     echo "⚠ install.sh não encontrado — pulei instalação, mas código já foi atualizado"
   fi
   ```

5. **Mostra CHANGELOG da nova versão.** Extrai a primeira seção de versão
   (até o próximo header) e imprime:

   ```bash
   # Primeiro bloco até encontrar próximo header (linha "## " ou "# ")
   awk '/^(#|##) /{if(seen++)exit}{print}' CHANGELOG.md
   ```

6. **Resumo final.**

   ```
   ✓ meta-ads-pro atualizado: v1.2.3 → v1.3.0
   Veja /meta-ads-doctor pra validar que nada quebrou no ambiente.
   ```

## Regras

- **Nunca `git pull --rebase` nem merge automático.** Só fast-forward.
  Quem quer customizar o plugin deve fazer fork.
- **Nunca `--force`** em nada.
- Falha de install.sh não aborta o comando — código atualiza primeiro, install
  é idempotente e pode re-rodar.

## Libs

Nenhuma — comando puro de shell.
