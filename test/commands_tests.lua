-- commands_tests.lua — cobertura do :calc (único utilitário de comando ativo).
-- Dispara o script via termux.run (mock => termux.calls); aqui valido o SCRIPT
-- exato (incl. quoting sh.shq) e o caminho de erro.
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local function load(name)
  return sandbox.load(name, { deps = sandbox.default_deps() })
end

local function C(name)
  local t = load(name)
  return sandbox.command(t, name), t
end

T.section("A. :calc")
local calc, tC = C("calc")
calc()
T.eq("sem expressão => uso", tC.vim.statuses[#tC.vim.statuses], "uso: :calc <expressão lua>  ex.: :calc 2+2*3")
calc("2+2*3")
T.eq("expressão quoteada num Lua 5.1", tC.deps.termux.calls[1], "lua5.1 -e 'print(2+2*3)'")
calc("math.max(3,7)+1")
T.eq("funções padrão OK", tC.deps.termux.calls[2], "lua5.1 -e 'print(math.max(3,7)+1)'")
calc("a'b")
T.eq("apóstrofo escapado no shq", tC.deps.termux.calls[3], "lua5.1 -e 'print(a'\\''b)'")

T.done("commands")