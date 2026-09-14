-- commands_tests.lua — cobertura dos utilitários :cat :files :ip :which :calc
-- :battery :sysinfo :todo :ping :pkg :weather :scroll. Cada um dispara scripts
-- via termux.run (mock => termux.calls) ou status direto; aqui valido o SCRIPT
-- exato (incl. quoting sh.shq) e os caminhos de erro.
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local TODO_HELP = "uso: :todo [add <texto> | del <n> | done <n>]  (sem nada: lista)"
local function shq_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- O mock padrão de termux.run grava os scripts em deps.termux.calls.
local function load(name)
  return sandbox.load(name, { deps = sandbox.default_deps() })
end

-- Shorthand: carga + comando registrado.
local function C(name)
  local t = load(name)
  return sandbox.command(t, name), t
end

T.section("A. :cat")
local cat, t = C("cat")
cat("~/storage/shared/Download/notas.txt")
T.eq("arquivo único quoteado", t.deps.termux.calls[1], "cat '~/storage/shared/Download/notas.txt'")
cat("/etc/hosts", "/etc/passwd")
T.eq("multi-arquivo: cada arg quoteado (não vira um caminho só)",
  t.deps.termux.calls[2], "cat '/etc/hosts' '/etc/passwd'")
cat("a'b")
T.eq("apóstrofo escapado no shq", t.deps.termux.calls[3], "cat 'a'\\''b'")

-- :cat sem argumento delega ao explorador do fzf (âncora) e vê o caminho escolhido.
T.section("B. :cat via fzf (âncora)")
local depsC = sandbox.default_deps()
local cexpl = {}
depsC.fzf.open_explorer = function(start, cb)
  cexpl[#cexpl + 1] = { start = start, cb = cb }
end
local ct = sandbox.load("cat", { deps = depsC })
local cat2 = sandbox.command(ct, "cat")
cat2()
T.eq(":cat sem arg abre o explorador na raiz (nil)", cexpl[1].start, nil)
cexpl[1].cb("/data/data/com.termux/files/root.txt")
T.eq("pick -> cat no caminho escolhido", ct.deps.termux.calls[1], "cat '/data/data/com.termux/files/root.txt'")

T.section("C. :ip")
local ip, tip = C("ip")
ip()
T.eq("script ifconfig -> ip fallback", tip.deps.termux.calls[1],
  "ifconfig 2>/dev/null | grep -E '(^[a-z]|inet )' || ip -4 addr 2>/dev/null")

T.section("D. :which")
local which, tW = C("which")
which()
T.eq("sem args => uso na status", tW.vim.statuses[#tW.vim.statuses], "uso: :which <programa>")
which("lua5.1", "ffmpeg")
T.eq("cada programa quoteado", tW.deps.termux.calls[1], "command -v 'lua5.1' 'ffmpeg'")

T.section("E. :calc")
local calc, tC = C("calc")
calc()
T.eq("sem expressão => uso", tC.vim.statuses[#tC.vim.statuses], "uso: :calc <expressão lua>  ex.: :calc 2+2*3")
calc("2+2*3")
T.eq("expressão quoteada num Lua 5.1", tC.deps.termux.calls[1], "lua5.1 -e 'print(2+2*3)'")
calc("math.max(3,7)+1")
T.eq("funções padrão OK", tC.deps.termux.calls[2], "lua5.1 -e 'print(math.max(3,7)+1)'")

T.section("F. :battery")
local battery, tB = C("battery")
battery()
T.is("lê power_supply", tB.deps.termux.calls[1]:find("/sys/class/power_supply") ~= nil)
T.is("fallback termux-battery-status", tB.deps.termux.calls[1]:find("termux-battery-status", 1, true) ~= nil)
T.is("aviso de instalação", tB.deps.termux.calls[1]:find("pkg install termux-api", 1, true) ~= nil)
T.is("timeout no fallback", tB.deps.termux.calls[1]:find("timeout 3") ~= nil)

T.section("G. :sysinfo")
local sysinfo, tS = C("sysinfo")
sysinfo("mem")
T.is("só memória", tS.deps.termux.calls[1]:find("free -h", 1, true) ~= nil)
T.is("não traz cpu", tS.deps.termux.calls[1]:find("model name") == nil)
sysinfo("CPU")
T.is("maiúsculas normalizadas", tS.deps.termux.calls[2]:find("model name") ~= nil)
sysinfo("disk")
T.is("só disco", tS.deps.termux.calls[3]:find("df -h", 1, true) ~= nil)
sysinfo()
T.is("sem arg => tudo (4 seções)", tS.deps.termux.calls[4]:find("== cpu ==") ~= nil
  and tS.deps.termux.calls[4]:find("== memória ==") ~= nil
  and tS.deps.termux.calls[4]:find("== disco ==") ~= nil
  and tS.deps.termux.calls[4]:find("== rede ==") ~= nil)

T.section("H. :todo")
local todo, tT = C("todo")
todo("list")
T.eq("lista numerada (tail 30)", tT.deps.termux.calls[1],
  "awk '{ printf \"%2d  %s\\n\", NR, $0 }' $HOME/.todo.txt | tail -30")
todo("listar")
T.eq("sub-comando desconhecido => uso", tT.vim.statuses[#tT.vim.statuses], TODO_HELP)
todo("add", "comprar", "pão")
T.eq("add: echo quoteado + tail 3", tT.deps.termux.calls[2],
  "echo 'comprar pão' >> $HOME/.todo.txt\nawk '{ printf \"%2d  %s\\n\", NR, $0 }' $HOME/.todo.txt | tail -3")
todo("add")
T.eq("add sem texto => uso", tT.vim.statuses[#tT.vim.statuses], TODO_HELP)
todo("del", "3")
T.eq("del numérico: sed", tT.deps.termux.calls[3], "sed -i 3d $HOME/.todo.txt")
todo("del", "abc")
T.eq("del não-numérico => uso", tT.vim.statuses[#tT.vim.statuses], "uso: :todo del <n>")
todo("done", "2")
T.eq("done numérico: sed com prefixo", tT.deps.termux.calls[4], "sed -i '2s/^/[x] /' $HOME/.todo.txt")

T.section("I. :ping")
local ping, tP = C("ping")
ping()
T.eq("sem host => uso", tP.vim.statuses[#tP.vim.statuses], "uso: :ping <host>")
ping("8.8.8.8")
T.eq("4 tentativas -W 3", tP.deps.termux.calls[1], "ping -c 4 -W 3 '8.8.8.8'")

T.section("J. :pkg")
local pkg, tK = C("pkg")
pkg()
T.eq("sem op => HELP", tK.vim.statuses[#tK.vim.statuses], "uso: :pkg search|install|remove|upgrade|list|info <alvos>")
local ops_ok = {
  { { "search", "gcc" },        "pkg search 'gcc'" },
  { { "install", "a", "b" },   "pkg install -y 'a' 'b'" },
  { { "remove", "x" },          "pkg uninstall -y 'x'" },
  { { "uninstall", "y" },       "pkg uninstall -y 'y'" },
  { { "del", "z" },             "pkg uninstall -y 'z'" },
  { { "upgrade" },              "pkg upgrade -y" },
  { { "list" },                 "pkg list-installed" },
  { { "info", "gcc" },          "pkg show 'gcc'" },
}
for i, c in ipairs(ops_ok) do
  pkg(unpack(c[1]))
  T.eq("op #" .. i .. " script", tK.deps.termux.calls[i], c[2])
end
pkg("force", "gcc")
T.eq("op inválida => HELP", tK.vim.statuses[#tK.vim.statuses], "uso: :pkg search|install|remove|upgrade|list|info <alvos>")

T.section("K. :weather")
local weather, tQ = C("weather")
weather("São", "Paulo")
T.eq("cidade vira +", tQ.deps.termux.calls[1], "curl -s -m 12 'wttr.in/São+Paulo?format=%l:+%c+%t+%w'")
weather()
T.eq("sem cidade => local (url vazia)", tQ.deps.termux.calls[2], "curl -s -m 12 'wttr.in/?format=%l:+%c+%t+%w'")
-- Injeção: a URL inteira vai quoteada (shq) — aspas/;$ viram parte da string.
weather("x'; rm -rf /; echo '")
T.eq("URL inteira sob shq (injeção neutralizada)", tQ.deps.termux.calls[3],
  "curl -s -m 12 " .. shq_escape("wttr.in/x';+rm+-rf+/;+echo+'?format=%l:+%c+%t+%w"))
T.is("' escapa no escopo interno do shq", tQ.deps.termux.calls[3]:find("x'\\'';+rm", 1, true) ~= nil)

T.section("L. :scroll")
local scroll, tR = C("scroll")
scroll()
T.eq("entra no modo scroll", tR.vim.modes[#tR.vim.modes], "scroll")

T.done("commands")