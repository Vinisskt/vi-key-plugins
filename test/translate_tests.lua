-- translate_tests.lua — cobertura do plugin :tr (tradução PT<->EN).
-- O mock de termux executa os callbacks SÍNCRONO (o mesmo comportamento que o
-- exec_async real teria quando o daemon responde) e grava cada comando para a
-- asserção do protocolo trans_*. Também cobre as funções puras via API.
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local function expected_cmd(args)
  return "if command -v trans >/dev/null 2>&1; then timeout 20 trans " .. args
    .. "; else echo 'TRANS_ERR_MISSING'; fi"
end

-- Termux mockável por estágio: cada chamada exec_async devolve a próxima saída.
local function mktermux(outs)
  local t = { i = 0, outs = outs or {}, cmds = {} }
  t.exec_async = function(cmd, cb)
    t.i = t.i + 1
    t.cmds[t.i] = cmd
    cb(t.outs[t.i])
  end
  return t
end

local function loadtr(flow, opts)
  local o = opts or {}
  local deps = o.deps or sandbox.default_deps()
  deps.termux = (type(flow) == "table" and flow.termux) and flow.termux or flow
  o.deps = deps -- força o termux mockado mesmo com get_text/get_sel custom
  return sandbox.load("translate", o)
end

local PT = "Portuguese"
local EN = "English"

T.section("A. registro e fluxo feliz com argumento")
local flow = {
  termux = mktermux({ PT, "olá" }),
}
local t = loadtr(flow)
local tr = sandbox.command(t, "tr")
T.is(":tr registrado", tr ~= nil)
tr("hello")
T.eq("identifica pt (flag -s pt)", flow.termux.cmds[1]:find("-identify -no-ansi 'hello'", 1, true) ~= nil, true)
T.eq("traduz p/ en (-s pt -t en)", flow.termux.cmds[2]:find("-s pt -t en", 1, true) ~= nil, true)
T.eq("envia resultado ao app", t.vim.sends[1], "olá")
T.eq("status de confirmação", t.vim.statuses[#t.vim.statuses], ":tr → olá")

T.section("B. comando trans exato (protocolo bash)")
T.eq("cmd identify exato", flow.termux.cmds[1], expected_cmd("-identify -no-ansi 'hello'"))
T.eq("cmd tradução exata", flow.termux.cmds[2], expected_cmd("-b -no-ansi -s pt -t en 'hello'"))

T.section("C. -v curto mostra status; -v longo abre página")
local f2 = { termux = mktermux({ EN, "this is a very short translation" }) }
local t2 = loadtr(f2)
sandbox.command(t2, "tr")("-v", "bonjour")
T.eq("-v curto: vim.status com o texto", t2.vim.statuses[#t2.vim.statuses], "this is a very short translation")
local f3 = { termux = mktermux({ EN, string.rep("x", 400) }) }
local t3 = loadtr(f3)
sandbox.command(t3, "tr")("-v", "bonjour")
T.eq("-v longo: vim.page", t3.vim.pages[1], string.rep("x", 400))

T.section("D. trans ausente (MISSING) => status de instalação, sem traduzir")
local f4 = { termux = mktermux({ "TRANS_ERR_MISSING" }) }
local t4 = loadtr(f4)
sandbox.command(t4, "tr")("oi")
T.eq("só 1 chamada (identify)", f4.termux.i, 1)
T.is("status de instalação", t4.vim.statuses[#t4.vim.statuses]:find("translate-shell", 1, true) ~= nil)
T.eq("nada enviado", #t4.vim.sends, 0)

T.section("E. rede (saída vazia) => status sem resposta")
local f5 = { termux = mktermux({ "" }) }
local t5 = loadtr(f5)
sandbox.command(t5, "tr")("oi")
T.eq("só identify", f5.termux.i, 1)
T.is("status de rede", t5.vim.statuses[#t5.vim.statuses]:find("internet") ~= nil)
T.eq("nada enviado", #t5.vim.sends, 0)

T.section("F. idioma detectado não-pt/en (detec) -> fallback heurístico")
local f6 = { termux = mktermux({ "French", "bonjour" }) }
local t6 = loadtr(f6)
sandbox.command(t6, "tr")("bonjour le monde")
T.eq("identify feito", f6.termux.i, 2)
T.eq("heurística -> source en (dst pt)", f6.termux.cmds[2]:find("-s en -t pt", 1, true) ~= nil, true)
T.eq("enviado", t6.vim.sends[1], "bonjour")

T.section("G. texto só com palavras-pivô pt -> source pt")
local f7 = { termux = mktermux({ "French", "oi" }) }
local t7 = loadtr(f7)
sandbox.command(t7, "tr")("isto é demais")
T.eq("heurística pt", f7.termux.cmds[2]:find("-s pt -t en", 1, true) ~= nil, true)

T.section("H. empate heurístico -> en")
local f8 = { termux = mktermux({ "French", "ok" }) }
local t8 = loadtr(f8)
sandbox.command(t8, "tr")("a the")
T.eq("empate -> en", f8.termux.cmds[2]:find("-s en -t pt", 1, true) ~= nil, true)

T.section("I. tradução idêntica -> tenta direção contrária e falha tudo")
local f9 = { termux = mktermux({ PT, "olá", "olá" }) }
local t9 = loadtr(f9)
sandbox.command(t9, "tr")("olá")
T.eq("3 chamadas (identify + 2 direções)", f9.termux.i, 3)
T.eq("segunda tentativa usou en", f9.termux.cmds[3]:find("-s en -t pt", 1, true) ~= nil, true)
T.eq("status sem tradução", t9.vim.statuses[#t9.vim.statuses], ":tr — sem tradução")
T.eq("nada enviado", #t9.vim.sends, 0)

T.section("J. idêntico na 1a, sucesso na 2a -> envia")
local f10 = { termux = mktermux({ PT, "olá", "hello" }) }
local t10 = loadtr(f10)
sandbox.command(t10, "tr")("olá")
T.eq("direção contrária funcionou", f10.termux.i, 3)
T.eq("enviado da 2a", t10.vim.sends[1], "hello")

T.section("K. seleção presente -> vim.replace no intervalo")
local o = { get_text = function() return "abc hello abc" end,
            get_sel = function() return 4, 9 end }
local f11 = { termux = mktermux({ EN, "Oi" }) }
local t11 = loadtr(f11, o)
sandbox.command(t11, "tr")()
T.eq("traduziu a seleção (hello)", f11.termux.cmds[1]:find("'hello'", 1, true) ~= nil, true)
T.eq("substitui intervalo sel", T.seqeq(t11.vim.repls[1], { 4, 9, "Oi" }), true)

T.section("L. sem args e sem seleção -> substitui o texto todo")
local o2 = { get_text = function() return "olá mundo" end,
             get_sel = function() return nil, nil end }
local f12 = { termux = mktermux({ PT, "hello world" }) }
local t12 = loadtr(f12, o2)
sandbox.command(t12, "tr")()
T.eq("replace(0, len, out)", T.seqeq(t12.vim.repls[1], { 0, 10, "hello world" }), true)

T.section("M. texto vazio -> status e nada")
local o3 = { get_text = function() return "   " end }
local f13 = { termux = mktermux({}) }
local t13 = loadtr(f13, o3)
sandbox.command(t13, "tr")()
T.eq("status texto vazio", t13.vim.statuses[#t13.vim.statuses], ":tr — texto vazio")
T.eq("nenhuma chamada termux", f13.termux.i, 0)

T.section("N. truncamento > MAX_CHARS (2500) anota a porção")
local f14 = { termux = mktermux({ EN, string.rep("y", 30) }) }
local t14 = loadtr(f14)
sandbox.command(t14, "tr")(string.rep("a", 2600))
T.is("cmds usaram só os 2500 primeiros", f14.termux.cmds[2]:find(string.rep("a", 2501)) == nil)
T.is("out anotado", t14.vim.sends[1]:find("porção inicial traduzida") ~= nil)

T.section("O. fallback síncrono (sem exec_async): usa termux.exec")
local sy = { i = 0, outs = { PT, "e aí" } }
sy.exec = function(cmd)
  sy.i = sy.i + 1
  sy.cmds = sy.cmds or {}
  sy.cmds[sy.i] = cmd
  return sy.outs[sy.i]
end
local t15 = loadtr(sy)
sandbox.command(t15, "tr")("oi amigo")
T.eq("2 execs síncronas", sy.i, 2)
T.equal = T.eq
T.eq("identify síncrono", sy.cmds[1]:find("-identify", 1, true) ~= nil, true)
T.eq("envia resultado", t15.vim.sends[1], "e aí")

T.section("P. funções puras via API")
local api = sandbox.load("translate", { deps = sandbox.default_deps() }).ret
T.section("P1. trans_cmd")
T.eq("trans_cmd envolve com guarda/timeout/MISSING",
  api.trans_cmd("-identify 'x'"),
  expected_cmd("-identify 'x'"))
T.section("P2. heur_src")
T.eq("frase en", api.heur_src("the world and the sea"), "en")
T.eq("frase pt", api.heur_src("isto é demais"), "pt")
T.eq("empate (a em ambas) -> en", api.heur_src("a"), "en")
T.eq("sem palavras-pivô -> en", api.heur_src("zxq asdf"), "en")
T.eq("vazio -> en", api.heur_src(""), "en")
T.eq("maiúsculas anotadas", api.heur_src("THE WORLD"), "en")
T.eq("pt com acento", api.heur_src("não é"), "pt")
T.section("P3. identify_out")
local ptos = api.identify_out("Código de língua: Portuguese\n...")
T.eq("Portugu -> pt", ptos, "pt")
T.equal = T.eq
local only = api.identify_out("English")
T.eq("English -> en", only, "en")
local enc = { api.identify_out("French") }
T.eq("outro idioma -> detec", enc[1], nil)
T.eq("motivo detec", (select(2, api.identify_out("French"))), "detec")
local first = (select(3, api.identify_out("French")))
T.eq("detec traz a 1a linha", first, "French")
T.eq("vazia -> net", select(2, api.identify_out("")), "net")
T.eq("nil -> net", select(2, api.identify_out(nil)), "net")
T.eq("MISSING -> missing", select(2, api.identify_out("TRANS_ERR_MISSING")), "missing")
T.section("P4. clean_trans")
T.eq("limpa ansi", api.clean_trans("\27[31mfoo\27[0m", "x"), "foo")
T.eq("tira espaços inicial/final", api.clean_trans("  bar  ", "x"), "bar")
T.eq("recolhe \n múltiplos", api.clean_trans("\noi\n\n", "x"), "oi")
T.eq("vazio -> nil", api.clean_trans("", "x"), nil)
T.eq("nil -> nil", api.clean_trans(nil, "x"), nil)
T.eq("MISSING -> nil c/ motivo", select(2, api.clean_trans("TRANS_ERR_MISSING", "x")), "instale translate-shell")
T.eq("ERROR -> nil", api.clean_trans("[ERROR] timeout", "x"), nil)
T.eq("idêntico byte-a-byte -> nil c/ motivo", select(2, api.clean_trans("olá mundo", "olá mundo")), "idêntico")
T.eq("caixa diferente ASCII -> idêntico (OI -> oi)", api.clean_trans("OI MUNDO", "oi mundo"), nil)
-- Limite conhecido: lower() (Lua 5.1, sem utf8) não rebaixa "Á"; maiúsculo
-- acentuado ≠ minúsculo em bytes -> passa como tradução.
T.eq("Á maiúsculo não rebate (byte-distinto)", api.clean_trans("OLÁ MUNDO", "olá mundo"), "OLÁ MUNDO")
T.eq("tradução real passa", api.clean_trans("olá\n", "hello"), "olá")

T.done("translate")