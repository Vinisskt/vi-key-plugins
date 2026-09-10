# vi-key-plugins

Plugins em Lua e daemon em C que transformam o teclado **vi-key** em uma ponte
para o **Termux**: do próprio teclado você roda comandos Linux, traduz, vê
bateria, rede, todo, clima e tudo mais — sem abrir aplicativo nenhum.

Funciona com o app vi-key (teclado personalizável com motor Lua embutido) rodando
no Android. Este repositório é a parte "do aparelho": os scripts que o teclado
carrega e o daemon que executa os comandos.

```
TELEFONE
┌────────────────────┐          /sdcard/keyboard-lua/
│  teclado vi-key    │──────────────────────────────► init.lua + plugins/*.lua
│  (app, Lua API)    │   lê/escreve data/cmd, out    (o teclado lê estes .lua)
│  vim.get_text etc. │
└─────────▲──────────┘
          │ data/ (arquivos de fila: cmd, busy, out, heartbeat, last-start)
          │
┌─────────┴──────────┐
│  daemon  vk-ipcd   │  C, supervisionado pelo runit (reinicia sozinho)
│  loop: pega cmd →  │  executa num FILHO → grava out → some busy
└────────────────────┘
```

## O que vem pronto

| Categoria | O que faz |
|-----------|-----------|
| `:termux <cmd>` / `:$` | executa qualquer comando no Termux e mostra a saída |
| `:->` | mostra a última saída salva |
| `:cat`, `:files`, `:which` | lê/lista arquivos, localiza executáveis |
| `:calc` | calculadora Lua (`:calc math.sqrt(2)`) |
| `:battery` | nível/status da bateria (Termux:API, com fallback por sysfs) |
| `:sysinfo [net/cpu/mem/disk]` | informações do aparelho |
| `:ip` | endereços de rede |
| `:todo [add/del/done]` | lista pessoal (`~/.todo.txt`) |
| `:ping <host>` | latência de rede |
| `:pkg <op> [alvos]` | pacotes do Termux |
| `:weather [cidade]` | previsão do tempo (wttr.in) |
| `:tr [texto]` | tradução PT↔EN (translate-shell/Google) |
| `:ipcloop` | status do daemon (heartbeat) |

O teclado **nunca trava**: os plugins só escrevem/leem arquivos em
`data/` e esperam um tempo curto; quem executa é o daemon num processo próprio.

## Instalação

Requisitos no Termux:

```sh
pkg install clang translate-shell termux-api lua5.1  # sugestão; só no aparelho
termux-setup-storage
pkg install termux-services   # se quiser o daemon sempre de pé (runit)
```

Depois, do diretório deste repositório:

```sh
sh install.sh
```

O `install.sh`:

1. confere/instala o compilador (`cc` vem com `clang` — libc nativa do Android,
   nada extra a instalar);
2. copia `init.lua` e `plugins/*.lua` para `/sdcard/keyboard-lua/` (pasta que o
   teclado lê) e garante a pasta `data/`;
3. compila o daemon `daemon/daemon.c` → `$PREFIX/bin/vk-ipcd`;
4. instala o serviço runit `vk-ipc` apontando para o binário (com o daemon Lua
   antigo como fallback) e o **(re)inicia**;
5. instala o hook de boot `~/.termux/boot/vk-ipc.sh` (só tem efeito com o app
   Termux:Boot instalado).

Depois **instale o teclado** (o projeto vi-key, `.apk` de debug) e conceda acesso
de armazenamento (Android pede na primeira inicialização). Pronto: `:termux
echo oi` no teclado deve mostrar `oi`.

> O teclado carrega os scripts ao abrir; se você editar os `.lua`, use o comando
> de recarga do teclado (ou reabra o teclado) para aplicar.

## Uso

Sintaxe geral: digite `:` no teclado e o nome do comando.

```sh
:termux uname -a          # sistema
:$ cat /proc/cpuinfo      # :$ é atalho para :termux
:->                       # mostra a saída do último comando
:tr "hello world"         # OLÁ MUNDO (tradução en→pt automática)
:tr how are you           # traduz o literal
:tr -v olá                # só mostra, não mexe no texto
:ping 1.1.1.1
:weather São Paulo
:todo add comprar café
```

### Sobre o `:tr`

- **texto**: argumentos → senão seleção → senão o texto todo;
- `:tr <texto>` devolve a tradução ao app (substitui a seleção; sem seleção,
  insere no cursor); texto todo só substitui se deu para traduzir tudo;
- `:tr -v [texto]` **só mostra** (status bar se curto, página rolável se longo);
- a direção (pt→en / en→pt) é detectada pelo próprio translate-shell
  (`trans -identify`), com acerto automático de direção quando o resultado sai
  idêntico ao original;
- precisa de internet (Google Translate). Sem `trans` ou sem rede, avisa o
  motivo exato.

## Arquitetura — protocolo dos arquivos

Tudo em `/sdcard/keyboard-lua/data/` (arquivo, não soquete: simples e robusto):

| arquivo      | significado |
|--------------|-------------|
| `cmd`        | comando a executar (o teclado escreve; some na hora da tomada) |
| `busy`       | "em execução" — o daemon renomeia `cmd`→`busy` (atômico) e só remove ao terminar |
| `out`        | saída (stdout+stderr) do comando |
| `heartbeat`  | epoch do loop do daemon — gravado **sempre**, até durante comando longo |
| `last-start` | epoch do início do comando (distingue "processando" de "morreu") |
| `stop`       | se presente, o daemon encerra limpo |

Fluxo de um comando:

1. o teclado grava `cmd` (escreve `cmd.tmp` e renomeia → atômico) e espera;
2. o daemon vê `cmd` sem `busy`, faz `rename(cmd → busy)` (só um pega), grava
   `out=""` e `last-start`;
3. executa o conteúdo de `busy` como script **num processo filho**
   (`bash busy > out 2>&1`) — o loop do daemon continua, escrevendo `heartbeat`
   a cada 0,3s;
4. filho termina → daemon remove `busy` = "concluído";
5. o teclado detecta `cmd` e `busy` ausentes e mostra `out`.

Por isso comandos longos nunca fazem parecer que o daemon morreu, e comandos
simultâneos nunca se misturam (fila de um só, com lock atômico).

## Desenvolvendo um plugin

Cada arquivo em `plugins/` é um módulo Lua simples:

```lua
local termux = require("termux")
local sh = require("shell")          -- sh.shq protege argumentos p/ o shell

vim.register("exemplo", function(...)
  local texto = tostring(... or "oi")
  termux.run({ "echo " .. sh.shq(texto) })
end)
```

- `termux.run({script})` executa e mostra; `termux.exec({script})` executa e
  **devolve** o texto (sem mostrar) — como o `:tr` usa;
- a saída curta (≤300c) vai para a barra de status; longa abre página rolável;
- comando que passa de ~3s entra em modo "acompanhando" (atualiza a cada 0,6s);
- **restrição**: a pasta está no armazenamento FUSE do Android — nomes de
  arquivo não podem conter `>`. O registro `vim.register("->", ...)` usa o nome
  na memória, então `:->` funciona normal.

Para testar sem o teclado, rode o daemon na mão e use o harness:

```sh
sv up vk-ipc                          # ou: $PREFIX/bin/vk-ipcd
lua5.1 plugins/cat.lua                # sintaxe das plugins (carrega teste?)
```

## Problemas comuns

| Sintoma | Causa / solução |
|---------|-----------------|
| `falta data/ (rode ipc-loop.lua)` | daemon não está rodando → `sv up vk-ipc` (runit) ou `$PREFIX/bin/vk-ipcd` |
| `termux sem resposta` | daemon desligado/veículo: veja `:ipcloop` (idade do heartbeat) |
| `sem resposta do trans (internet?)` | `:tr` sem rede ou `trans` lento; `timeout 20` protege o daemon |
| comando some / nada acontece | confira permissão de armazenamento do teclado (Android) |
| daemon morre por conta própria | roda sob runit → reinicia em <2s; `sv status vk-ipc` mostra |

## Segurança

O daemon executa **como script** o que o teclado escrever em `data/cmd`. Isso é o
recurso (rodar comandos Linux do teclado), mas significa: o acesso de
armazenamento do teclado + este daemon equivalem a poder executar comandos no
seu Termux. Só instale este repositório em aparelhos seus.

## Licença

Este projeto é feito para uso pessoal (veja o app vi-key). Distribuído como
está, sem garantias.