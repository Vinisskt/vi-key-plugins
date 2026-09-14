# Auditoria vi-key-plugins

Auditoria + correções + ampliação de testes de `~/Projects/vi-key-plugins`.
Tudo rodando em **lua5.1** (mesmo runtime do teclado). Suíte completa:
`./test/run.sh`.

## Bugs corrigidos (com teste cobrindo cada um)

1. **`:weather` — injeção de shell na cidade.** `shq(cidade)` protegia o nome,
   mas a URL era montada e passada SEM aspas: `wttr.in/Sao` era `"curl -s -m 12 `
   .. wttr.in/..` — a cidade (`Sao; rm -rf ...`) trocava de contexto. Agora a
   **URL inteira** vai sob `sh.shq` (plugins/weather.lua:12).
2. **`:cat` multi-arquivo.** `:cat a b` virava um caminho único `cat a b`
   (arquivo chamado "a b"). Agora cada argumento é quoteado separadamente
   (plugins/cat.lua:19-21).
3. **`:tr` travava o teclado.** `termux.exec` esperando a resposta síncrona por
   até 6s **congela o IME** (busy-wait na thread da UI); `:tr` fazia identify +
   1-2 traduções = até ~12s de freeze. Refatorado para assíncrono com
   `termux.exec_async` + `vim.interval` (plugins/translate.lua:72-104), com
   fallback síncrono só em teclados sem a API. Mesma mudança no início de
   navegação do `fzf` (`M.run`).
4. **`:theme` registrado em duplicidade** (dracula.lua e tokyo.lua) — vencia o
   que carregava por último (ordem do init.lua). Centralizado em gruvbox.lua
   (tema padrão) e ganhou tratamento de `off`.
5. **`tail_lines` com `n-1` linhas + `\n` sobrando.** A captura vazia do `\n`
   final entrava na conta e o status do follow mostrava menos linhas e um
   newline residual. Agora limpa `\n+$` antes (plugins/termux.lua:47-56).
6. **`heur_src` cego para pivôs acentuados.** `%a` no locale C só casa ASCII:
   "é", "não", "está" nunca contavam como português. Boa parte das frases pt
   detectava en. Adicionada detecção por substring crua (plugins/translate.lua).
7. **`:tr` com texto só-de-espaços.** Colapsava para `" "` (≠ `""`) e tentava
   traduzir. Feito trim antes do teste de vazio.
8. **Escopo quebrado no termux.lua.** O `submit()` chamava `follow_stop`, que
   era um `local function` declarado *depois* — no load, `submit` resolvia
   `follow_stop` como global (nil) → erro em runtime. Movido para depois das
   funções de follow.

## Otimizações de latência

- **Worker persistente** (data/worker-loop.sh + FIFO): o bash nasce UMA vez e
  fica lendo o FIFO; por comando só há um `eval` + write de arquivo — a maior
  redução de latência (contra spawn de bash por comando). Mantido como estava.
- **`M.exec_async`** no padrão do `termux` + `vim.interval` deixam o teclado
  livre enquanto o comando roda; `follow_tick` acompanha longos (`pkg upgrade`,
  `ping`) mostrando as últimas 5 linhas (também corrigido o limite acima).
- `:tr` async (identify → tradução → retry na direção contrária), sem os
  bloqueios anteriores.

## Verificações que NÃO viraram mudança (ok no código)

- **daemon.c**: worker mantém o fd 3 aberto durante o `eval` → heartbeat não
  para (sem "daemon morto" falso). FIFO/criação/flags conferidos. Não alterado.
- **`:ip` passa STRING** a `termux.run` — `run` normaliza `table/string`
  (plugins/termux.lua:211-215).
- **Filas por arquivo**: `os.remove(cmd)` antes do `rename` = fila
  last-write-wins; o daemon toma com `mv` atômico e o `busy` só some quando o
  worker conclui. Sem corrida destrutiva.
- **Escapamento**: `:calc` / `:todo add` / `:ping` / `:pkg` quotes individuais
  via `sh.shq`; o `'\''` reintra a string — sem vazamento de contexto.

## Pontos de atenção (marcar no aparelho)

- **`:ipcloop` — worker.pid sob `/data/data/com.termux/.../var/vk-ipc`** (dir
  app-private). O status do teclado pode dizer "worker morto" mesmo com o
  daemon vivo por falta de permissão de leitura. Vale abstrair o canal
  (ex.: guardar o pid junto do data/ no /sdcard).
- **`:pkg info`** usa `pkg show` — confirmar que `show` existe no pkg oficial
  do Termux (senão trocar por `apt show`/`pkg search`).
- **`:theme` agora vive em gruvbox.lua**: quem desativar o gruvbox perde o
  `:theme` (dracula/tokyo só têm o comando próprio).
- **Limites de heartbeat discrepantes** entre `exec` (8s), `run` (4s) e
  `follow_tick` (6s) — por design (inicia cedo, para tarde), mas dá para
  alinhar em uma constante.
- **`clean_trans` compara bytes**: `string.lower` (Lua 5.1) não rebaixa
  acentos — `OLÁ` ≠ `olá`. Limite conhecido sem lib utf8.

## Cobertura de testes (nova infra + suítes)

Infra: `test/runner.lua` (mini framework: ok/eq/contains/seqeq/shq/done) e
`test/sandbox.lua` (env isolado, mocks de vim/termux/shell/fzf). Documenta o
footgun do Lua 5.1 (`local x = { f = function() x end }` resolve `x` global no
construtor — declarar o local antes).

| Suíte | Asserções | Cobre |
|---|---|---|
| fzf_tests.lua | 124 | preexistente (navegação/início) |
| shell_tests.lua | 15 | shq/quotes |
| termux_tests.lua | 54 | exec/exec_async/run/timeout/follow/tail_lines — seams `set_data`/`_now`/`_daemon_done`/`_tail_lines` |
| translate_tests.lua | 63 | pt/en/detec/missing/net/idêntico→contrária/`-v`/seleção/truncamento/fallback sync + puras (trans_cmd/heur_src/clean_trans/identify_out) via API |
| commands_tests.lua | 46 | cat/files/ip/which/calc/battery/sysinfo/todo/ping/pkg/weather/scroll — scripts exatos + injeção |
| themes_tests.lua | 35 | paletas, comandos, `:theme` único, `off` |
| ipcloop_tests.lua | 9 | status heartbeat/worker (ok/morto) via `set_env` |
| smoke_tests.lua | 1 | carrega TODOS os plugins + registros |
| **total** | **347** | **0 falhas** |

API exposta p/ testes (sem mudar comportamento): `termux.set_data/get_data`,
`_now`, `_daemon_done`, `_tail_lines`; `ipc-loop.set_env(data,var)`;
`translate.trans_cmd/heur_src/clean_trans/identify_out`.
## Mudança de conceito: fzf = âncora (API pura)

Decisão do usuário (13/09): o fzf deixa de ser um comando do teclado e vira a
**âncora de busca/seleção** para outros plugins. Ele só navega, filtra e
**entrega a escolha por callback** — nunca roda nada por conta própria.

O que mudou:

- **`fzf.lua` é API** (sem `vim.register`): nenhum comando `:fzf` no teclado.
  - `open_explorer([caminho], on_pick)`: Enter em pasta navega; em **arquivo**
    chama `on_pick(caminho_absoluto)`. Sem callback, Enter fecha e **nada roda**
    (antes o arquivo era executado via `termux.run`).
  - `run({comando...}, on_pick)`: modo comando agora também recebe callback;
    Enter chama `on_pick(linha)` ou fecha. O aviso "enter roda" no cabeçalho só
    aparece quando há callback.
- **`cat.lua`** mantém `:cat` e ganha `cat.view(...)` (API):
  - `:cat <caminho>` continua vendo direto (vários args = vários arquivos).
  - `:cat` sem argumento abre o explorador do fzf e lê o arquivo escolhido
    (`on_pick` → `cat.view`).
- **`files.lua` removido**: `plugins/files.lua` apagado e `"files"` saiu do
  `init.lua` — navegar + ver arquivos é papel do `:cat`.

Testes acompanharam: harness do fzf sem assert de registro (API pura), todos os
casos "Enter roda" viram "Enter sem callback não roda", seção `:files` removida
dos commands_tests, seção nova `:cat sem arg via fzf`, smoke confere que o fzf
registra ZERO comandos, e caso novo K4 cobre `run({...}, cb)` (callback recebe a
linha; `termux.run` não é chamado). `:cat`/picker seguem cobrindo ponta a ponta.

| Suíte | Asserções | Ajuste |
|---|---|---|
| fzf_tests.lua | 125 | +1 (K4) −2 (L2/L2b — :files) |
| commands_tests.lua | 44 | −4 (:files) +2 (:cat via fzf) |
| smoke_tests.lua | 3 | −2 (files/fzf comando) +2 (fzf API pura) |
| **total** | **348** | **0 falhas** |

## Plugins de ferramentas (âncora fzf)

Novos plugins que só fazem o papel de AÇÃO sobre a âncora `fzf` (nunca rodam
nada sozinhos; o picker entrega a escolha por callback):

- **`rg.lua` — `:rg <padrão> [dir]`**: busca no home (padrão) ou em [dir] com
  `rg -n --no-heading -S` (smart-case). O padrão/dir vão quoteados com `sh.shq`
  e o home tripé `"$HOME"` em aspas duplas (expande no bash). Enter num
  resultado `caminho:linha:conteúdo` mostra a linha do match via
  `sed -n '<n>p' '<arquivo>'`.
- **`hist.lua` — `:hist`**: lista `$HOME/.bash_history` do mais recente (`tac`)
  e Enter RODA a linha escolhida — o texto vai CRUO ao `termux.run` (são
  command words; shq quebraria aspas/encadeamentos do próprio comando).
- **`du.lua` — `:du [dir]`**: `du -h -a -d 1 <dir> | sort -hr` com um `while`
  que marca pastas com "/" no fim. Enter em pasta aprofunda (re-chama o du
  naquela dir); Enter em arquivo vê via `cat.view`. Arquivo>pasta por não ter
  "/" no fim (linhas com tamanho<TAB>caminho).

Decisões de isolamento:
- `du` depende de `cat` (`require("cat")`) para reusar a visão central — o
  sandbox ganhou o mock padrão `cat.view` (espelha `termux.run`).
- Filtro/inalável: linhas fora do formato esperado são ignoradas (não crasham).

Novas limitações conhecidas:
- `rg` assume saída `caminho:linha:conteúdo` (padrão do `--no-heading`); um
  nome de arquivo contendo ":" quebra a primeira posição (raro no Termux).
- `du` re-lista a raiz se você Enter nela própria (no-op, sem loop).

| Suíte | Asserções | Ajuste |
|---|---|---|
| tools_tests.lua | 22 | :rg / :hist / :du (pick, quoting, Enter-entrega) |
| smoke_tests.lua | 3 | +rg/+hist/+du nos comandos esperados |
| **total** | **370** | **0 falhas** |

## Mais ferramentas com a âncora (2ª leva — para teste do usuário)

- **`man.lua` — `:man <comando> [seção]`**: direto (não usa picker) — monta
  `man 'cmd' ['sec']` com cada arg sob `sh.shq`. Saída longa vira página
  (termux.run).
- **`snip.lua` — `:snip`**: cola snippet no cursor. Lê `~/.snippets`
  (formato `nome<TAB>texto`, uma por linha) via fzf; Enter → `vim.send(texto)`
  (API de inserção no cursor que o translate já usa). Linha sem tab cola a
  linha inteira.
- **`ps.lua` — `:ps`**: lista `ps -A` no picker e Enter executa `kill <pid>`.
  Blindagem: pid "1" e linhas sem pid só avisam (`:ps — linha sem pid`) —
  nunca matam. É a "âncora de matar": o usuário decide se quer manter.

Fix durante os testes (lição): em `line:find("^(.-)\t(.*)$")` há DUAS capturas
— o `texto` é a SEGUNDA. Destructuring correto:
`local _, _, _, texto = line:find(...)` (o 4º retorno). Pegar só 3 retornos
devolve a primeira captura (o nome) e "cola o nome".

| Suíte | Asserções | Ajuste |
|---|---|---|
| tools_tests.lua | 36 | +man/+snip (cola + sem tab)/+ps (kill, blindagens) |
| smoke_tests.lua | 3 | +man/+snip/+ps nos comandos esperados |
| **total** | **384** | **0 falhas** |
