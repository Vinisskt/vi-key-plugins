-- shell_tests.lua — cobertura do plugin shell (shq/run).
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

T.section("A. shq(): argumento literal seguro no bash")
local t = sandbox.load("shell")
T.is("plugin carrega e volta tabela", type(t.ret) == "table" and type(t.ret.shq) == "function")
T.is("M.shq exposto", type(t.ret.shq) == "function")

local shq = t.ret.shq
T.section("A1. casos bom / médio / horríveis")
T.eq("palavra simples", shq("lua"), "'lua'")
T.eq("caminho com espaço", shq("~/meu arquivo.txt"), "'~/meu arquivo.txt'")
T.eq("aspas simples escapadas", shq("it's"), "'it'\\''s'")
T.eq("aspas no meio", shq("a'b'c"), "'a'\\''b'\\''c'")
T.eq("vazio", shq(""), "''")
T.eq("nulo vira ''", shq(nil), "''")
T.eq("numero vira string", shq(42), "'42'")
T.eq("unicode preservado", shq("olá mundo"), "'olá mundo'")
T.eq("traco de injeção fica dentro das aspas", shq("x; rm -rf ~; #"), "'x; rm -rf ~; #'")

-- A string gerada NUNCA deixa um N de aspas sem fechar e contém '\\'' quando
-- existia aspas simples (o escape real do shell).
local evil = shq("';touch /tmp/opencode-pwn;'")
T.is("escape de aspas presente", evil:find("'\\''") ~= nil)
T.is("ponto-e-virgula nao sai das aspas", evil:match("^'") ~= nil and evil:sub(-1) == "'")

T.section("B. M.run delega para termux.run")
local tb = sandbox.load("shell")
tb.ret.run("echo oi")
T.eq("run repassa script", tb.deps.termux.calls[1], "echo oi")
T.eq("run com espaço preserva", tb.deps.termux.calls[1], "echo oi")

T.done("shell")