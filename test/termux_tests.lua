-- termux_tests.lua — cobertura do núcleo da ponte (protocolo cmd/out/busy).
-- Usa uma data/ TEMPORÁRIA (M.set_data) e injeção de relógio/fim-da-fila
-- (M._now, M._daemon_done) para simular o daemon sem esperar 6s de verdade.
local os = os
local io = io
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local uid = 0
local function fresh_data()
  uid = uid + 1
  -- Suffixo único: os.time tem resolução de 1s e várias pastas nascem no mesmo
  -- segundo na mesma execução (senão colidiriam e vazariam estado entre seções).
  local dir = "/tmp/vk-termux-test-" .. tostring(os.time()) .. "-" .. tostring(uid)
  os.execute("mkdir -p '" .. dir .. "'")
  return dir
end

local function tmpfile(dir, name, content)
  local f = io.open(dir .. "/" .. name, "w")
  if f then f:write(content); f:close() end
end

local function exists(dir, name)
  local f = io.open(dir .. "/" .. name, "r")
  if f then f:close(); return true end
  return false
end

-- Sequência falsa de relógio: começa em [start] e sobe [delta] a cada chamada.
local function fake_clock(start, delta)
  local v = start
  return function()
    v = v + delta
    return v
  end
end

T.section("A. registros de comandos")
local base = sandbox.load("termux")
T.eq("qtd registros", #base.vim.registrations, 3)
local names = {}
for _, r in ipairs(base.vim.registrations) do names[#names + 1] = r.n end
T.eq("comandos termux/$/->", T.seqeq(names, { "termux", "$", "->" }), true)
T.eq("termux registrado", sandbox.command(base, "termux") ~= nil, true)
T.eq("$ registrado", sandbox.command(base, "$") ~= nil, true)
T.eq("-> registrado", sandbox.command(base, "->") ~= nil, true)

T.section("B. M.exec — caminho feliz (daemon 'pronto' na hora)")
local dir = fresh_data()
local t = sandbox.load("termux")
t.deps.termux = nil -- termux.lua não requer nada; só vim e arquivos importam
t.ret.set_data(dir)
tmpfile(dir, "out", "echo oi\n")
-- Injeta "concluído = true" para o loop não esperar: o exec escreve o cmd de
-- verdade e devolve a saída já gravada.
local M = t.ret
local done_flag = true
M._daemon_done = function() return done_flag end
M._now = fake_clock(1000, 1)
local out = M.exec("echo oi")
T.eq("exec devolve out limpo", out, "echo oi")
-- O comando foi escrito na fila (no sandbox o daemon mockado não consome o
-- cmd — ele É criado, ó o ponto: o protocolo de escrita tmp->rename funciona).
local f = io.open(dir .. "/cmd", "r")
T.is("cmd escrito na fila", f ~= nil)
if f then
  T.eq("conteúdo do cmd", f:read("*l"), "echo oi")
  f:close()
end
T.is("cmd.tmp não fica para trás (rename atômico)", not exists(dir, "cmd.tmp"))
T.is("busy não é criado pelo teclado", not exists(dir, "busy"))
os.remove(dir .. "/cmd") -- limpa p/ as seções seguintes no mesmo dir

T.section("C. M.exec — aceita tabela de args e junta com espaço")
tmpfile(dir, "out", "ok\n")
T.eq("exec com tabela", M.exec({ "echo", "a b" }), "ok")

T.section("D. M.exec — comando vazio devolve nil sem escrever")
local d2 = fresh_data()
local m2 = sandbox.load("termux")
m2.ret.set_data(d2)
m2.ret._now = fake_clock(2000, 1)
T.eq("exec vazio = nil", m2.ret.exec(""), nil)
T.eq("exec nil = nil", m2.ret.exec(nil), nil)
T.eq("exec {} = nil", m2.ret.exec({}), nil)
T.is("nada escrito", not exists(d2, "cmd") and not exists(d2, "cmd.tmp"))

T.section("E. M.exec — timeout sem resposta (daemon morto)")
local d3 = fresh_data()
local m3 = sandbox.load("termux")
m3.ret.set_data(d3)
m3.ret._daemon_done = function() return false end
m3.ret._now = fake_clock(3000, 2) -- ~1.5s de diferença por chamada; estoura 6s
local outT = m3.ret.exec("sleep 9")
T.eq("exec timeout = nil", outT, nil)
T.eq("status avisa sem resposta", m3.vim.statuses[#m3.vim.statuses], "termux sem resposta (rode ipc-loop.lua no Termux)")

T.section("F. M.exec — timeout mas daemon vivo (heartbeat fresco) -> follow_start")
local d4 = fresh_data()
local m4 = sandbox.load("termux")
m4.ret.set_data(d4)
tmpfile(d4, "heartbeat", tostring(3000))
m4.ret._daemon_done = function() return false end
local n = 0
-- Relógio que estoura os 6s do exec mas mantém o heartbeat com <=8s de idade:
-- os 3 primeiros usos sobem até 3000+7 (diff 6 -> sai do loop) e o último fica
-- em 3000+8 (idade do hb = 8, ainda "vivo").
m4.ret._now = function() n = n + 1; return 3000 + math.min(n, 8) end
local outF = m4.ret.exec("pkg upgrade -y")
T.eq("exec timeout com hb fresco = nil", outF, nil)
-- follow_start(b) -> status_hold "processando..." e registra vim.interval(300,...)
T.eq("hold de follow gravado", m4.vim.holds[#m4.vim.holds], "termux: processando...")
T.eq("vim.interval usado p/ follow (300ms)", m4.vim.intervals[1].ms, 300)

T.section("G. M.exec — heartbeat velho + cmd pendente = daemon morto")
local d5 = fresh_data()
local m5 = sandbox.load("termux")
m5.ret.set_data(d5)
tmpfile(d5, "heartbeat", tostring(1000)) -- 3000 - 1000 > 8
m5.ret._daemon_done = function() return false end
m5.ret._now = fake_clock(3000, 2)
T.eq("timeout com hb velho = nil", m5.ret.exec("pkg upgrade -y"), nil)
T.eq("status avisa daemon", m5.vim.statuses[#m5.vim.statuses], "termux sem resposta (rode ipc-loop.lua no Termux)")

T.section("H. M.exec_async — conclui via vim.interval")
local d6 = fresh_data()
local m6 = sandbox.load("termux")
m6.ret.set_data(d6)
tmpfile(d6, "out", "resultado\n")
m6.ret._daemon_done = function() return true end
m6.ret._now = fake_clock(4000, 1)
local done6
m6.ret.exec_async("comando x", function(out) done6 = out end)
T.eq("async: 1 intervalo registrado (50ms)", m6.vim.intervals[1].ms, 50)
T.is("async: intervalo com callback", type(m6.vim.intervals[1].cb) == "function")
-- dispara o poll manualmente (simula o vim.interval rodando)
m6.vim.intervals[1].cb()
T.eq("async: ondone com resultado", done6, "resultado")
T.is("async: clear_interval ao concluir", m6.vim.n_cleared >= 1)

T.section("I. M.exec_async — timeout com daemon morto -> ondone(nil)")
local d7 = fresh_data()
local m7 = sandbox.load("termux")
m7.ret.set_data(d7)
m7.ret._daemon_done = function() return false end
local n7 = 0
m7.ret._now = function() n7 = n7 + 1; return 5000 + n7 * 10 end -- >6s e hb morto
local ok7
m7.ret.exec_async("longo", function(out) ok7 = out end)
T.is("async: intervalo criado", #m7.vim.intervals == 1)
m7.vim.intervals[1].cb()
T.eq("async: ondone nil no timeout", ok7, nil)
T.eq("async: status de erro", m7.vim.statuses[#m7.vim.statuses], "termux sem resposta (rode ipc-loop.lua no Termux)")
T.is("async: clear_interval", m7.vim.n_cleared >= 1)

T.section("J. M.exec_async — comando vazio chama ondone(nil) direto")
local d8 = fresh_data()
local m8 = sandbox.load("termux")
m8.ret.set_data(d8)
local got8 = "provisorio"
m8.ret.exec_async("", function(o) got8 = o end)
T.eq("async vazio -> nil", got8, nil)
T.eq("nenhum intervalo", #m8.vim.intervals, 0)

T.section("K. M.exec_async — sem vim.interval cai no exec síncrono")
local d9 = fresh_data()
local m9 = sandbox.load("termux", { no_interval = true })
m9.ret.set_data(d9)
tmpfile(d9, "out", "sync\n")
m9.ret._daemon_done = function() return true end
m9.ret._now = fake_clock(6000, 1)
local got9
m9.ret.exec_async("x", function(o) got9 = o end)
T.eq("fallback sync", got9, "sync")

T.section("L. M.run — sem args mostra a última saída")
local d10 = fresh_data()
local m10 = sandbox.load("termux")
m10.ret.set_data(d10)
m10.ret.run({}) -- sem out
T.eq("run sem args e sem out: status", m10.vim.statuses[#m10.vim.statuses], "(sem saída ainda — envie um comando com :termux)")
tmpfile(d10, "out", "curto")
m10.ret.run({})
T.eq("run sem args com out <=300: status", m10.vim.statuses[#m10.vim.statuses], "curto")
tmpfile(d10, "out", string.rep("x", 301))
m10.ret.run({})
T.eq("run com out >300: vim.page", m10.vim.pages[1], string.rep("x", 301))

T.section("M. M.run — com comando, daemon pronto -> mostra saída")
local d11 = fresh_data()
local m11 = sandbox.load("termux")
m11.ret.set_data(d11)
tmpfile(d11, "out", "oi")
m11.ret._daemon_done = function() return true end
m11.ret._now = fake_clock(7000, 1)
m11.ret.run({ "echo", "oi" })
T.eq("run mostra out", m11.vim.statuses[#m11.vim.statuses], "oi")
local fc = io.open(d11 .. "/cmd", "r")
T.is("run escreveu o cmd na fila", fc ~= nil)
if fc then T.eq("run conteúdo do cmd", fc:read("*l"), "echo oi"); fc:close() end

T.section("N. M.run — comando pendente + daemon vivo -> follow")
local d12 = fresh_data()
local m12 = sandbox.load("termux")
m12.ret.set_data(d12)
tmpfile(d12, "heartbeat", tostring(8000))
m12.ret._daemon_done = function() return false end
local n12 = 0
-- Caminha de 8000+1 até 8000+4: estoura o timeout de 3s do run (~4 de diff)
-- mantendo a idade do heartbeat em 4 (ainda <= 4 => follow, não "sem resposta").
m12.ret._now = function() n12 = n12 + 1; return 8000 + math.min(n12, 4) end
m12.ret.run({ "pkg", "upgrade" })
T.eq("run pendente com hb fresco: follow hold", m12.vim.holds[#m12.vim.holds], "termux: processando...")
T.eq("follow usa intervalo 300ms", m12.vim.intervals[1].ms, 300)

T.section("O. M.run — pendente + daemon morto -> aviso")
local d13 = fresh_data()
local m13 = sandbox.load("termux")
m13.ret.set_data(d13)
tmpfile(d13, "heartbeat", tostring(1000))
m13.ret._daemon_done = function() return false end
m13.ret._now = fake_clock(9000, 2)
m13.ret.run({ "algo" })
T.eq("run morto: status", m13.vim.statuses[#m13.vim.statuses], "termux sem resposta (rode ipc-loop.lua no Termux)")

T.section("P. M.show — out vazio / faltando")
local d14 = fresh_data()
local m14 = sandbox.load("termux")
m14.ret.set_data(d14)
m14.ret.show()
T.eq("show sem out: status", m14.vim.statuses[#m14.vim.statuses], "(sem saída ainda — envie um comando com :termux)")
tmpfile(d14, "out", "   \n")
m14.ret.show()
T.eq("show out vazio: status", m14.vim.statuses[#m14.vim.statuses], "(vazio)")

T.section("Q. tail_lines (seam M._tail_lines)")
local tl = base.ret._tail_lines
T.eq("menos que n linhas", tl("a\nb\n", 5), "a\nb")
T.eq("mais que n: descarta as primeiras", tl("l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\n", 5), "l4\nl5\nl6\nl7\nl8")
T.eq("linha única sem \\n final", tl("só", 5), "só")
T.eq("linha única com \\n final (sem \\n sobrando)", tl("só\n", 5), "só")
T.eq("muitos \\n finais recolhidos", tl("x\n\n\n", 3), "x")
T.eq("vazio", tl("", 5), "")
T.eq("nil vira vazio", tl(nil, 5), "")

T.section("R. registro -> M.run usado pelo comando")
local d15 = fresh_data()
local m15 = sandbox.load("termux")
m15.ret.set_data(d15)
tmpfile(d15, "out", "estático")
m15.ret._daemon_done = function() return true end
m15.ret._now = fake_clock(10000, 1)
local cmd_termux = sandbox.command(m15, "termux")
cmd_termux("echo", "hi")
T.eq(":termux via registro escreve e mostra", m15.vim.statuses[#m15.vim.statuses], "estático")
local cmd_dollar = sandbox.command(m15, "$")
cmd_dollar("ls", "-la")
T.eq(":$ via registro", m15.vim.statuses[#m15.vim.statuses], "estático")
local cmd_arrow = sandbox.command(m15, "->")
cmd_arrow()
T.eq(":-> via registro", m15.vim.statuses[#m15.vim.statuses], "estático")

T.done("termux")