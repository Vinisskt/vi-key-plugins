# plugins/dicionario — `:dict`

Correção automática de acentos e pequenos erros de digitação em Português, sem
sugestões: ao comitar uma palavra (espaço/pontuação) que casa ≥70% com o
dicionário, ela é substituída pela forma canônica via `vim.replace`.

- `:dict` → estado; `:dict on|off` → liga/desliga; `:dict status` → detalhes;
  `:dict <palavra>` → mostra a correção (não edita).
- Durante a digitação o índice é cortado pela metade por busca binária no
  prefixo digitado (`intervalo_por_prefixo`), então a correção só examina a
  faixa restante.
- Os offsets do `vim.get_sel`/`vim.replace` são em **bytes** (UTF-8): o módulo
  anda por caracteres completos (`inicio_char`), nunca deixa cortar um acento.

## Dados

O índice vem **embutido** em `plugins/dicionario_dados.lua` (módulo Lua gerado,
versionado): o `:dict` funciona 100% offline — nada é baixado nem gerado no
aparelho. O módulo devolve uma única string `chave<TAB>canonical\n...`
**ordenada pela chave**:

```
voce	você
nao	não
cafe	café
```

- **chave** = letras base, minúsculas, sem acento (só a-z → busca binária por
  prefixo usa `"{"` como limite superior);
- **canonical** = a forma com acento.

O plugin primeiro tenta `require("dicionario_dados")`; se o app não achar o
módulo, cai para `dados_dir/dicionario.dat` (mesmo formato, para quem quiser um
índice próprio).

## Regenerar o módulo (só para atualizar o vocabulário)

Num PC/Termux com rede — isso não ocorre nunca no aparelho:

```sh
# fonte: lista de frequência do português (palavras reais, c/ conjugações)
curl -fsSLo /tmp/pt_50k.txt \
  https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2016/pt/pt_50k.txt

lua5.1 ../../scripts/gera_dicionario.lua /tmp/pt_50k.txt /tmp/dicionario.dat \
  ../../dicionario_dados.lua
```

O gerador aceita também `.dic` do Hunspell (`palavra/flags`) e listas puras.

## Testes

`lua5.1 test/dicionario_tests.lua` (49 asserções com mocks de `vim`); rodo todo
pelo `./test/run.sh` na raiz.