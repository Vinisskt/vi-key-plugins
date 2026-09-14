-- tools_tests.lua — plugins de ferramentas com a âncora fzf: :rg :hist :du.
-- Rode:  lua5.1 test/tools_tests.lua
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

-- deps com fzf que captura as chamadas de run() (args + cb) e cat fake que
-- registra os arquivos vistos. O padrão do sandbox já tem termux/shell.
local function make_deps()
  local deps = sandbox.default_deps()
  local runs, viewed = {}, {}
  deps.fzf.run = function(args, cb) runs[#runs + 1] = { args = args, cb = cb } end
  deps.fzf.open_explorer = function() end
  deps.cat = { view = function(p) viewed[#viewed + 1] = p end }
  return deps, runs, viewed
end

T.section("A. :rg")
local deps, runs = make_deps()
local rg = sandbox.load("rg", { deps = deps })
local rgcmd = sandbox.command(rg, "rg")
rgcmd()
T.eq("sem padrão => uso", rg.vim.statuses[#rg.vim.statuses],
  "uso: :rg <padrão> [dir]  (dir opcional; padrão = home)")
T.is("e não abre picker", #runs == 0)

rgcmd("fun", "ação")
T.eq("lista rg c/ padrão e dir quoteados", table.concat(runs[1].args, " "),
  "rg -n --no-heading -S 'fun' 'ação'")
runs[1].cb("src/a.lua:12:local x = 1")
T.eq("Enter mostra a linha do match", rg.deps.termux.calls[1],
  "sed -n '12p' 'src/a.lua'")

rgcmd("hello world")
T.eq("padrão com espaço quoteado", runs[2].args[5], "'hello world'")
T.eq("sem dir => busca no home", runs[2].args[6], '"$HOME"')
T.is("padrão injetado segue sob shq", runs[2].args[5]:find("'", 1, true) ~= nil
  and table.concat(runs[2].args, " "):find(";", 1, true) == nil)

rgcmd("a'b")
T.is("apóstrofo escapado no shq", runs[3].args[5]:find("'a'\\''b'", 1, true) ~= nil)

T.section("B. :hist")
local deps2, runs2 = make_deps()
local hist = sandbox.load("hist", { deps = deps2 })
local histcmd = sandbox.command(hist, "hist")
histcmd("x")
T.eq("args => uso", hist.vim.statuses[#hist.vim.statuses],
  "uso: :hist  (o filtro do fzf já busca no histórico)")
histcmd()
T.eq("lista histórico do mais recente", table.concat(runs2[1].args, " "),
  'tac "$HOME/.bash_history"')
runs2[1].cb("ls -la")
T.eq("Enter roda a linha crua (command words)", hist.deps.termux.calls[1], "ls -la")

T.section("C. :du")
local deps3, runs3, viewed = make_deps()
local du = sandbox.load("du", { deps = deps3 })
local ducmd = sandbox.command(du, "du")
ducmd()
local script1 = table.concat(runs3[1].args, " ")
T.is("começa no home expandido", script1:find('"$HOME"', 1, true) ~= nil)
T.is("du -h -a -d 1 (pastas + arquivos)", script1:find("du -h -a -d 1", 1, true) ~= nil)
T.is("sort por tamanho humano", script1:find("sort -hr", 1, true) ~= nil)
T.is("pasta marcada com '/' no fim", script1:find('p="$p/"', 1, true) ~= nil)
T.is("linha tab separada", script1:find("%s\\t%s", 1, true) ~= nil)

runs3[1].cb("1.2G\t/data/data/com.termux/files/home/docs/")
T.is("pasta aprofunda nela", table.concat(runs3[2].args, " "):find("'/data/data/com.termux/files/home/docs'", 1, true) ~= nil)

runs3[2].cb("12K\t/data/data/com.termux/files/home/docs/notas.txt")
T.eq("arquivo vê por :cat (view)", viewed[1], "/data/data/com.termux/files/home/docs/notas.txt")
T.is("e não reabre picker", #runs3 == 2)

runs3[1].cb("lixo-inválido  ")
T.eq("linha fora do formato: ignora", viewed[2] == nil and #runs3 == 2, true)

ducmd("/sdcard")
T.is("arg vira raiz quoteada", table.concat(runs3[3].args, " "):find("'/sdcard'", 1, true) ~= nil)
ducmd()
T.is("sem arg (de novo) volta a $HOME", table.concat(runs3[4].args, " "):find('"$HOME"', 1, true) ~= nil)

T.section("D. :snip")
local deps4, runs4 = make_deps()
local snip = sandbox.load("snip", { deps = deps4 })
local snipcmd = sandbox.command(snip, "snip")
snipcmd("x")
T.eq("args => uso", snip.vim.statuses[#snip.vim.statuses],
  "uso: :snip  (edite ~/.snippets: uma 'nome<TAB>texto' por linha)")
snipcmd()
T.eq("lista os snippets", table.concat(runs4[1].args, " "), 'cat "$HOME/.snippets"')
runs4[1].cb("aso\tiface wifi")
T.eq("Enter cola o texto no cursor", snip.vim.sends[#snip.vim.sends], "iface wifi")
runs4[1].cb("linha sem tab")
T.eq("linha sem tab cola inteira", snip.vim.sends[#snip.vim.sends], "linha sem tab")

T.section("E. :ps")
local deps5, runs5 = make_deps()
local psmod = sandbox.load("ps", { deps = deps5 })
local pscmd = sandbox.command(psmod, "ps")
pscmd("x")
T.eq("args => uso", psmod.vim.statuses[#psmod.vim.statuses],
  "uso: :ps  (Enter no processo executa kill <pid>)")
pscmd()
T.eq("lista os processos", table.concat(runs5[1].args, " "), "ps -A")
runs5[1].cb("  123 sshd")
T.eq("Enter mata o pid", psmod.deps.termux.calls[1], "kill 123")
T.eq("...e confirma na status", psmod.vim.statuses[#psmod.vim.statuses], ":ps → kill 123")
runs5[1].cb("? erro")
T.eq("linha sem pid: só aviso, não mata", psmod.deps.termux.calls[2] == nil
  and psmod.vim.statuses[#psmod.vim.statuses] == ":ps — linha sem pid", true)
runs5[1].cb("    1 init")
T.eq("pid 1 é blindado (não mata o sistema)", psmod.deps.termux.calls[2] == nil
  and psmod.vim.statuses[#psmod.vim.statuses] == ":ps — linha sem pid", true)

T.section("F. :man")
local man = sandbox.load("man", { deps = sandbox.default_deps() })
local mancmd = sandbox.command(man, "man")
mancmd()
T.eq("sem comando => uso", man.vim.statuses[#man.vim.statuses], "uso: :man <comando> [seção]")
mancmd("ls")
T.eq("roda man quoteado", man.deps.termux.calls[1], "man 'ls'")
mancmd("5", "crontab")
T.eq("seção + comando", man.deps.termux.calls[2], "man '5' 'crontab'")
mancmd("a'b")
T.eq("apóstrofo escapado", man.deps.termux.calls[3], "man 'a'\\''b'")

T.done("tools")