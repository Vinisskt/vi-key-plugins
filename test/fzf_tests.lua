-- fzf_tests.lua — cobertura total do plugin fzf (saída esperada E saída errada).
-- Rode:  lua5.1 test/fzf_tests.lua     (sai 0 = ok, 1 = falhas)
--
-- Cada cenario recarrega o plugin num ambiente isolado (setfenv) com mocks de
-- vim/termux/shell, para o estado interno do fzf nunca vazar entre testes.
local PLUGIN = "plugins/fzf.lua"

local pass, fail = 0, 0
local failures = {}

local function ok(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures + 1] = name
    print("  FALHOU: " .. name)
  end
end

local function eq(name, a, b)
  ok(name .. " (obtive <" .. tostring(a) .. ">, quero <" .. tostring(b) .. ">)", a == b)
end

-- Igualdade profunda de arrays (para comparar as chamadas de termux.run).
local function seqeq(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    if not seqeq(a[i], b[i]) then return false end
  end
  return true
end

local function shq(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local HOME = "/data/data/com.termux/files/home"
-- Gera o comando "ls -A -p '<caminho absoluto>'" com o mesmo quoting real.
local function ls(d) return "ls -A -p " .. shq(d) end

-- Cold-start do explorador: resolve $HOME e lista a raiz num unico exec.
-- $HOME em aspas duplas expande no bash (igual no plugin).
local function homef()
  return "printf '%s\\n' \"$HOME\"; ls -A -p \"$HOME\""
end

-- Mapa fs com todo o caminho de pais de HOME (cada um listando "sub/"),
-- terminando em "/". Útil para exercitar a subida até a raiz.
local function home_chain_fs()
  local f = {}
  f[homef()] = HOME .. "\n" .. "sub/"
  f[ls(HOME)] = "sub/"
  local d = HOME
  while true do
    f[ls(d)] = "sub/"
    if d == "/" then break end
    d = d:match("(.*)/[^/]+$") or "/"
  end
  return f
end

-- Cria ambiente+mocks novos e carrega o plugin.
local function fresh(fs, opts)
  opts = opts or {}
  local vim
  local termux
  vim = {
    registrations = {}, statuses = {}, holds = {}, modes = {}, hooks = {},
    nhook = 0,
    register    = function(n, f) vim.registrations[#vim.registrations + 1] = { n, f } end,
    status      = function(s) vim.statuses[#vim.statuses + 1] = s end,
    set_mode    = function(m) vim.modes[#vim.modes + 1] = m end,
  }
  if not opts.no_key_hook then
    vim.key_hook = function(f)
      vim.nhook = vim.nhook + 1
      vim.hooks[vim.nhook] = f
    end
  end
  if not opts.no_status_hold then
    vim.status_hold = function(s) vim.holds[#vim.holds + 1] = s end
  end
  termux = {
    calls = {}, runs = {}, pending = {},
    exec = function(c)
      termux.calls[#termux.calls + 1] = c
      if c == "echo $HOME" then return HOME .. "\n" end
      return fs[c]
    end,
    -- async: por padrao responde sincrono (fixture); com defer_async, segura
    -- o callback em termux.pending para o teste disparar quando quiser.
    exec_async = function(c, cb)
      termux.calls[#termux.calls + 1] = c
      if opts.defer_async then
        termux.pending[#termux.pending + 1] = { c = c, cb = cb }
        return
      end
      cb(fs[c])
    end,
    run  = function(a) termux.runs[#termux.runs + 1] = a end,
  }
  local env = { vim = vim }
  env.require = function(name)
    if name == "termux" then return termux end
    if name == "shell" then return { shq = shq } end
  end
  setmetatable(env, { __index = _G })
  local chunk = assert(loadfile(PLUGIN))
  setfenv(chunk, env)
  local mod = assert(chunk(), "plugin carrega")
  assert(#vim.registrations == 0, "fzf e API pura: nao registra comando")
  -- O fzf virou ancora (sem comando). O "cmd" abaixo repete o papel do antigo
  -- ":fzf" como atalho p/ a API run({}) e deixa os testes de comportamento
  -- (navegacao, filtro, cabecalho) iguais aos de um plugin que o chama.
  return { vim = vim, termux = termux, cmd = function(...) mod.run({ ... }) end, mod = mod }
end

-- Helpers de inspeção sobre a última janela renderizada.
local function split(s)
  local r = {}
  for l in string.gmatch(s .. "", "[^\n]+") do r[#r + 1] = l end
  return r
end
local function head(s) return (split(s)[1]) end
local function rows(s)
  local l = split(s)
  table.remove(l, 1)
  return l
end
-- Junta linhas com "|" para comparar a lista inteira por valor.
local function jl(s)
  return table.concat(rows(s), "|")
end
local function curitem(s)
  local l = split(s)
  for i = 1, #l do
    if l[i]:sub(1, 2) == "> " then return l[i]:sub(3) end
  end
end
-- Última janela renderizada via status_hold e hook registrado mais recente.
local function lasthold(t) return t.vim.holds[#t.vim.holds] end
local function hook(t) return t.vim.hooks[t.vim.nhook] end

-----------------------------------------------------------------------
print("== A. Carga e registros ==")

do
  local t = fresh({})
  eq("A1 fzf nao registra comando (API pura)", #t.vim.registrations, 0)
  eq("A2 sem key_hook: run() bloqueia e avisa", (function()
    local t2 = fresh({}, { no_key_hook = true })
    t2.vim.statuses = {}
    t2.cmd()
    return #t2.vim.statuses == 1 and t2.vim.statuses[1]:find("requer atual", 1, true) and t2.termux.calls[1] == nil
  end)(), true)
  eq("A3 sem key_hook: comando tambem bloqueia", (function()
    local t2 = fresh({ ["ls"] = "a" }, { no_key_hook = true })
    t2.cmd("ls")
    return t2.termux.calls[1] == nil and t2.vim.statuses[#t2.vim.statuses]:find("requer atual", 1, true) ~= nil
  end)(), true)
  eq("A4 fallback p/ vim.status quando nao ha status_hold", (function()
    local t2 = fresh({ [homef()] = HOME .. "\n" .. "storage/" }, { no_status_hold = true })
    t2.cmd()
    return t2.vim.statuses[1]:find("fzf 2/2", 1, true) ~= nil
  end)(), true)
end

-----------------------------------------------------------------------
print("== B. Explorador (API run) — saida esperada ==")

local FS_B = {
  [homef()] = HOME .. "\n" .. "storage/\nbin/\nprojetos\nnotas.txt",
  [ls(HOME)] = "storage/\nbin/\nprojetos\nnotas.txt",
}
do
  local t = fresh(FS_B)
  t.cmd()
  eq("B1 resolve $HOME e lista num exec", t.termux.calls[1], homef())
  eq("B1b one-shot cold start (1 exec)", #t.termux.calls, 1)
  eq("B2 header mostra 2/5 e @~", head(t.vim.holds[#t.vim.holds]), "fzf 2/5  @~")
  local r = rows(t.vim.holds[#t.vim.holds])
  eq("B3 '..' primeiro", r[1], "  ..")
  eq("B3b cursor em storage/ (cur=2)", r[2], "> storage/")
  eq("B4 hook registrado e modo scroll", t.vim.nhook == 1 and t.vim.modes[#t.vim.modes] == "scroll", true)

  eq("B5 up sobe p/ '..'", (function() assert(hook(t)("up")); return curitem(t.vim.holds[#t.vim.holds]) end)(), "..")
  eq("B5b header 1/5", head(t.vim.holds[#t.vim.holds]), "fzf 1/5  @~")

  eq("B6 up no topo permanece", (function() assert(hook(t)("up")); return head(t.vim.holds[#t.vim.holds]) end)(), "fzf 1/5  @~")
  eq("B7 down ate o fim e cursor visivel", (function()
    for _ = 1, 4 do assert(hook(t)("down")) end
    return curitem(t.vim.holds[#t.vim.holds])
  end)(), "notas.txt")
  eq("B7b header 5/5", head(t.vim.holds[#t.vim.holds]), "fzf 5/5  @~")

  eq("B8 down clampa no fim (nao passa)", (function()
    assert(hook(t)("down"))
    assert(hook(t)("down"))
    return curitem(t.vim.holds[#t.vim.holds])
  end)(), "notas.txt")

  eq("B9 tecla desconhecida nao e consumida", (function()
    local n0 = #t.vim.holds
    local ret = hook(t)("F1")
    return ret == false and #t.vim.holds == n0
  end)(), true)
end

do
  -- B10 sessao quente usa cache de $HOME: so executa o ls (1 exec, sem echo)
  local t = fresh(FS_B)
  t.cmd()
  assert(hook(t)("esc"))
  t.cmd()
  eq("B10 2a sessao usa ls direto (cache)", t.termux.calls[2], ls(HOME))
  eq("B10b sem nova resolucao (2 execs no total)", #t.termux.calls, 2)
  eq("B10c header normal", head(t.vim.holds[#t.vim.holds]), "fzf 2/5  @~")
end

-----------------------------------------------------------------------
print("== C. API run({comando}) — saida esperada ==")

local FS_C = { ["pkg list-installed"] = "alsa-utils\nzip\nzsh" }
do
  local t = fresh(FS_C)
  t.cmd("pkg", "list-installed")
  eq("C1 exec exatamente o comando", t.termux.calls[1], "pkg list-installed")
  eq("C2 header 1/3 sem @ (sem callback: nada roda)", head(t.vim.holds[#t.vim.holds]), "fzf 1/3")
  local r = rows(t.vim.holds[#t.vim.holds])
  eq("C3 primeira linha selecionada", r[1], "> alsa-utils")
  eq("C4 enter sem callback: nada roda", (function() assert(hook(t)("down")); assert(hook(t)("down")); assert(hook(t)("enter")); return #t.termux.runs == 0 end)(), true)
  eq("C4b enter: hook limpo + modo insert", t.vim.nhook == 2 and t.vim.modes[#t.vim.modes] == "insert", true)

  local t2 = fresh(FS_C)
  t2.cmd("pkg", "list-installed")
  assert(hook(t2)("enter"))
  eq("C5 enter sem callback nao roda", #t2.termux.runs, 0)

  local t3 = fresh(FS_C)
  t3.cmd("pkg", "list-installed")
  eq("C6 esc cancela sem rodar", (function()
    assert(hook(t3)("esc"))
    return #t3.termux.runs == 0 and t3.vim.modes[#t3.vim.modes] == "insert"
      and t3.vim.statuses[#t3.vim.statuses] == "fzf: cancelado"
  end)(), true)
end

-----------------------------------------------------------------------
print("== D. Explorador: descer / subir / arquivo ==")

local FS_D = {
  [homef()]                    = HOME .. "\n" .. "storage/\nbin/\nprojetos\nnotas.txt",
  [ls(HOME)]                 = "storage/\nbin/\nprojetos\nnotas.txt",
  [ls(HOME .. "/storage/")]  = "downloads/\nstorage.png\ndocs/",
  [ls(HOME .. "/storage/docs/")] = "readme.md\nfotos/",
  [ls(HOME .. "/storage")]   = "downloads/\nstorage.png\ndocs/",
  [ls(HOME:match("(.*)/[^/]+$"))] = "sdcard/\netc/",
  [ls("/")]             = "sdcard/\netc/\nhome/",
  [ls(HOME .. "/my dir/")]   = "file.txt",
}
do
  local t = fresh(FS_D)
  t.cmd()
  -- desce storage/
  assert(hook(t)("enter"))
  eq("D1 desce p/ ~/storage/", t.termux.calls[2], ls(HOME .. "/storage/"))
  eq("D1b header @~/storage/", head(t.vim.holds[#t.vim.holds]), "fzf 2/4  @~/storage/")
  eq("D1c rows: .. , > downloads/", (function()
    local r = rows(t.vim.holds[#t.vim.holds])
    return r[1] == "  .." and r[2] == "> downloads/"
  end)(), true)
  -- entra docs/ (sobe de ~/storage/: .., downloads/, storage.png, docs/ -> docs e o ultimo)
  assert(hook(t)("down"))
  assert(hook(t)("down"))
  assert(hook(t)("enter"))
  eq("D2 aninhado p/ docs/", t.termux.calls[3], ls(HOME .. "/storage/docs/"))
  eq("D2b header", head(t.vim.holds[#t.vim.holds]), "fzf 2/3  @~/storage/docs/")
  -- roda readme (cur=2) — caminho absoluto (antes: 'readme.md' relativo ao HOME)
  assert(hook(t)("enter"))
  eq("D3 arquivo sem callback: nada roda", #t.termux.runs, 0)
  eq("D3b hook limpo + insert", t.vim.hooks[t.vim.nhook] == nil and t.vim.modes[#t.vim.modes] == "insert", true)

  -- sobe de ~/storage/docs
  local t2 = fresh(FS_D)
  t2.cmd()
  assert(hook(t2)("enter"))
  assert(hook(t2)("down"))
  assert(hook(t2)("down"))
  assert(hook(t2)("enter"))
  assert(hook(t2)("up")) -- .. (docs)
  assert(hook(t2)("enter"))
  eq("D4 '..' de docs -> ~/storage", t2.termux.calls[4], ls(HOME .. "/storage"))
  eq("D4b header", head(t2.vim.holds[#t2.vim.holds]), "fzf 2/4  @~/storage")
  assert(hook(t2)("up"))
  assert(hook(t2)("enter"))
  eq("D5 '..' volta p/ ~", t2.termux.calls[5], ls(HOME))
  eq("D5b header", head(t2.vim.holds[#t2.vim.holds]), "fzf 2/5  @~")
  assert(hook(t2)("up"))
  assert(hook(t2)("enter"))
  eq("D6 '..' de ~ sobe p/ o pai real", t2.termux.calls[6], ls(HOME:match("(.*)/[^/]+$")))
  eq("D6b header com caminho absoluto", head(t2.vim.holds[#t2.vim.holds]), "fzf 2/3  @/data/data/com.termux/files")

  -- diretório com espaço: verifica o quoting no ls via um fresh com mapa proprio
  local t4 = fresh({ [homef()] = HOME .. "\n" .. "my dir/\nprojetos", [ls(HOME .. "/my dir/")] = "file.txt" })
  t4.cmd()
  assert(hook(t4)("enter"))
  eq("D7 dir com espaco e quotado no exec", t4.termux.calls[2], ls(HOME .. "/my dir/"))
  eq("D7b header do dir com espaco", head(t4.vim.holds[#t4.vim.holds]), "fzf 2/2  @~/my dir/")
end

-----------------------------------------------------------------------
print("== E. Saidas erradas / malformadas ==")

do
  -- E1 comando que retorna nil
  local t = fresh({ ["boom"] = nil })
  t.cmd("boom")
  eq("E1 nil -> sem resultado, sem hook, sem crash", (function()
    return t.vim.statuses[1] == "fzf: sem resultado (comando >6s ou nada na saída)"
      and t.vim.hooks[1] == nil and t.termux.calls[1] == "boom"
  end)(), true)

  -- E2 comando que retorna vazio
  local t2 = fresh({ ["vacuo"] = "" })
  t2.cmd("vacuo")
  eq("E2 '' tb avisa sem resultado", t2.vim.statuses[1] == "fzf: sem resultado (comando >6s ou nada na saída)" and t2.vim.hooks[1] == nil, true)

  -- E3 dir sem acesso no explorador
  local tf = fresh({ [homef()] = HOME .. "\n" .. "storage/" })
  tf.cmd()
  assert(hook(tf)("enter"))
  eq("E3 dir inacessivel avisa e mantem hook", (function()
    return tf.vim.statuses[#tf.vim.statuses]:find("sem acesso", 1, true) ~= nil
      and hook(tf) ~= nil
  end)(), true)
  eq("E3b esc apos falha cancela sem crash", (function()
    assert(hook(tf)("esc"))
    return tf.vim.statuses[#tf.vim.statuses] == "fzf: cancelado"
  end)(), true)

  -- E4 diretório vazio no explorador -> so ".."
  local t4 = fresh({ [homef()] = HOME .. "\n" .. "empty/", [ls(HOME .. "/empty/")] = "" })
  t4.cmd()
  assert(hook(t4)("enter"))
  eq("E4 dir vazio vira '..' sozinho", head(t4.vim.holds[#t4.vim.holds]), "fzf 1/1  @~/empty/")
  eq("E4b linha '..'", curitem(t4.vim.holds[#t4.vim.holds]), "..")

  -- E5 saida so com quebras de linha
  local t5 = fresh({ ["linhas"] = "\n\n\n" })
  t5.cmd("linhas")
  eq("E5 so quebras -> sem resultado", t5.vim.statuses[1] == "fzf: sem resultado" and t5.vim.nhook == 1, true)

  -- E6 MAX_ITEMS = 200
  do
    local many = {}
    for i = 1, 250 do many[#many + 1] = "item-" .. i end
    local t6 = fresh({ ["many"] = table.concat(many, "\n") })
    t6.cmd("many")
    eq("E6 cabe em 200", head(t6.vim.holds[#t6.vim.holds]), "fzf 1/200")
    local h6 = hook(t6)
    for _ = 1, 199 do assert(h6("down")) end
    eq("E6b cursor no ultimo, visivel", curitem(t6.vim.holds[#t6.vim.holds]), "item-200")
  end

  -- E7 linhas longas clipadas
  do
    local long = string.rep("x", 60)
    local t7 = fresh({ ["longo"] = long })
    t7.cmd("longo")
    local r = curitem(t7.vim.holds[#t7.vim.holds])
    eq("E7 clip em 40 chars (12 + ~ + 27)", #r, 40)
    eq("E7b prefixo preservado", r:sub(1, 8), string.sub(long, 1, 8))
    eq("E7c NOME DO ARQUIVO (cauda) preservado", r:sub(-8), string.sub(long, -8))
    eq("E7d '~' no meio (recorte do meio)", r:find("~", 1, true), 13)
  end

  -- E8 trailing newline seguro
  local t8 = fresh({ [homef()] = HOME .. "\n" .. "storage/\nbin/\n" })
  t8.cmd()
  eq("E8 trailing \\n nao cria item vazio", head(t8.vim.holds[#t8.vim.holds]), "fzf 2/3  @~")

  -- E9 hook stale apos esc (estado inativo)
  do
    local t9 = fresh({ ["um"] = "parte1\nparte2" })
    t9.cmd("um")
    local h = hook(t9)
    assert(h("esc"))
    local n0 = #t9.vim.holds
    local ret = h("j") -- gancho velho depois de cancelado
    eq("E9 hook velho devolve false e limpa", ret == false and t9.vim.nhook == 3 and #t9.vim.holds == n0, true)
  end

  -- E10 CRLF (malformado) nao quebra
  do
    local t10 = fresh({ ["crlf"] = "alpha\r\nbeta\r\n" })
    t10.cmd("crlf")
    eq("E10 CRLF vira 2 itens", head(t10.vim.holds[#t10.vim.holds]), "fzf 1/2")
  end
end

-----------------------------------------------------------------------
print("== F. Re-render / janela no meio da lista ==")

do
  local many = {}
  for i = 1, 200 do many[#many + 1] = "linha-" .. i end
  local t = fresh({ ["lista"] = table.concat(many, "\n") })
  t.cmd("lista")
  -- j 99x para chegar em linha-100
  local h = hook(t)
  for _ = 1, 99 do assert(h("down")) end
  local w = rows(t.vim.holds[#t.vim.holds])
  eq("F1 janela mostra linhas 98..101", w[1], "  linha-98")
  eq("F1b", w[2], "  linha-99")
  eq("F1c cursor na 3a linha da janela", w[3], "> linha-100")
  eq("F1d", w[4], "  linha-101")
  eq("F2 cursor linha-100 visivel", curitem(t.vim.holds[#t.vim.holds]), "linha-100")
end

-- Confere PONTO EXATO do cursor: na janela, a linha com '>' eh a linha que DEVE estar sob o cursor.
-- Verificamos equivalência: curitem(hold) == item na posição cur. Como cur nao e exposto, checamos
-- que a linha '>' existe e ela é sempre igual ao 2o dado quando top<cur<top+3? para simplificar,
-- revalidamos no caso central F1: esperado "linha-100" (documentado acima).

-----------------------------------------------------------------------
print("== G. parent() / subida em / ==")

do
  local t = fresh(home_chain_fs())
  t.cmd()
  assert(hook(t)("up")) -- .. (de ~)
  assert(hook(t)("enter"))
  eq("G1 '..' de ~ -> pai", t.termux.calls[2], ls(HOME:match("(.*)/[^/]+$")))
  -- continua subindo: sempre chega em / e de / nunca sai
  for _ = 1, 10 do
    assert(hook(t)("up"))
    assert(hook(t)("enter"))
  end
  eq("G2 subindo sempre chega e fica em /", t.termux.calls[#t.termux.calls], ls("/"))
end

-----------------------------------------------------------------------
print("== H. Casos limite ==")

do
  -- H1 linha vazia no meio nao vira item
  local t = fresh({ ["miolo"] = "a\n\nb" })
  t.cmd("miolo")
  eq("H1 linha vazia no meio ignorada", head(t.vim.holds[#t.vim.holds]), "fzf 1/2")

  -- H2 explorador com 300 itens -> 200 itens + ".." no topo
  local many = {}
  for i = 1, 300 do many[#many + 1] = "item-" .. i end
  local t2 = fresh({ [homef()] = HOME .. "\n" .. table.concat(many, "\n"), [ls(HOME)] = table.concat(many, "\n") })
  t2.cmd()
  eq("H2 explorador cabe 200 (+.. = 201)", head(t2.vim.holds[#t2.vim.holds]), "fzf 2/201  @~")
  local h2 = hook(t2)
  for _ = 1, 199 do assert(h2("down")) end
  eq("H2b ultimo item visivel no fim", curitem(t2.vim.holds[#t2.vim.holds]), "item-200")

  -- H3 base longa clusteriza no header (clip 40: meio cortado, fim preservado)
local longname = "pasta-com-nome-bem-grande-que-excede-o-clip"
local t3 = fresh({
  [homef()] = HOME .. "\n" .. longname .. "/",
  [ls(HOME .. "/" .. longname .. "/")] = "x/",
})
t3.cmd()
assert(hook(t3)("enter"))
local hh = head(t3.vim.holds[#t3.vim.holds])
eq("H3 base clipada a 40 (apos o @)", #hh, #("fzf 2/2  @") + 40)
eq("H3b base comeca com ~/pasta-", hh:find("@~/pasta-", 1, true) ~= nil, true)
eq("H3c cauda do path preservada", hh:sub(-8), string.sub("~/" .. longname .. "/", -8))

  -- H4 back com query vazia nao cancela (backspace so apaga); esc cancela
  local t4 = fresh({ ["x"] = "1" })
  t4.cmd("x")
  local r4 = hook(t4)("back")
  eq("H4 back sem query segue ativo e consumido", r4 == true and t4.vim.statuses[#t4.vim.statuses] ~= "fzf: cancelado", true)
  assert(hook(t4)("esc"))
  eq("H4b esc cancela", t4.vim.statuses[#t4.vim.statuses] == "fzf: cancelado" and #t4.termux.runs == 0, true)

  -- H5 nova sessao apos esc recomeca em cur=2 (e usa o cache de $HOME)
  local t5 = fresh({ [homef()] = HOME .. "\n" .. "storage/\nbin/\nprojetos\nnotas.txt", [ls(HOME)] = "storage/\nbin/\nprojetos\nnotas.txt" })
  t5.cmd()
  assert(hook(t5)("esc"))
  t5.cmd()
  eq("H5 nova sessao recomeca em cur=2", head(t5.vim.holds[#t5.vim.holds]), "fzf 2/5  @~")
  eq("H5b 2a sessao usa ls direto (cache)", t5.termux.calls[2], ls(HOME))

  -- H6 explorador com diretorio de um arquivo so
  local t6 = fresh({ [homef()] = HOME .. "\n" .. "solo.txt" })
  t6.cmd()
  eq("H6 um arquivo + .. = 2 itens", head(t6.vim.holds[#t6.vim.holds]), "fzf 2/2  @~")
  assert(hook(t6)("enter"))
  eq("H6b arquivo sem callback: nada roda", #t6.termux.runs, 0)

  -- H7 diretorio cujo item termina com "/" dir com espaco e enter repetido em .. (sobe ate / e fica)
  local t7 = fresh(home_chain_fs())
  t7.cmd()
  for _ = 1, 10 do
    assert(hook(t7)("up"))
    assert(hook(t7)("enter"))
  end
  eq("H7 '..' repetido estaciona em /", t7.termux.calls[#t7.termux.calls], ls("/"))
end

-----------------------------------------------------------------------
print("== I. Filtro de digitacao / setas ==")

do
  -- I1 filtro em modo comando filtra a propria saida (nao busca no home)
  local t = fresh({ ["pkg list-installed"] = "alsa-utils\nzip\nzsh", [ls(HOME)] = "storage/" })
  t.cmd("pkg", "list-installed")
  assert(hook(t)("z"))
  assert(hook(t)("s"))
  eq("I1 modo comando filtra", head(t.vim.holds[#t.vim.holds]), "fzf 1/1  'zs'")
  assert(hook(t)("enter"))
  eq("I1b enter sem callback nao roda", #t.termux.runs, 0)
  eq("I1c sem find (modo comando)", t.termux.calls[#t.termux.calls], "pkg list-installed")
end

do
  -- I2 filtro case-insensitive e backspace no modo comando
  local t = fresh({ ["pkg list-installed"] = "alsa-utils\nzip\nzsh" })
  t.cmd("pkg", "list-installed")
  for _, c in ipairs({ "Z", "S" }) do assert(hook(t)(c)) end
  assert(hook(t)("enter"))
  eq("I2 case-insensitive filtra, enter nao roda", #t.termux.runs, 0)

  local t2 = fresh({ ["pkg list-installed"] = "alsa-utils\nzip\nzsh" })
  t2.cmd("pkg", "list-installed")
  assert(hook(t2)("z"))
  assert(hook(t2)("s"))
  assert(hook(t2)("back"))
  eq("I3 backspace volta p/ 'z' (2 matches)", head(t2.vim.holds[#t2.vim.holds]), "fzf 1/2  'z'")
end

-----------------------------------------------------------------------
print("== J. Busca recursiva no home inteiro ==")

-- Comando "find" do indice (parenteses escapados p/ shell).
local function findf()
  return "find " .. shq(HOME) ..
    " -maxdepth 8 \\( -name 'node_modules' -prune \\) -o \\( -type f -print \\)"
end

local FS_J = {
  [homef()] = HOME .. "\n" .. "storage/\nbin/\nprojetos\nnotas.txt",
  [findf()] = HOME .. "/storage/calc.txt\n" .. HOME .. "/docs.txt\n" .. HOME .. "/jogo.dat",
}

do
  -- J1 digitar filtra no home inteiro (indice 1x + caminho relativo + @~)
  local t = fresh(FS_J)
  t.cmd()
  assert(hook(t)("c"))
  eq("J1 busca usa find no home (1x, apos o cold-start)", t.termux.calls[2], findf())
  eq("J1b header @~", head(t.vim.holds[#t.vim.holds]), "fzf 1/2  @~  'c'")
  eq("J1c linhas: pasta+arquivo com ~", jl(t.vim.holds[#t.vim.holds]), "> ~storage/calc.txt|  docs.txt")

  -- J2 enter roda o arquivo pelo caminho absoluto
  assert(hook(t)("enter"))
  eq("J2 enter sem callback: nada roda", #t.termux.runs, 0)

  -- J2b seta move o cursor nos resultados da busca
  local t2 = fresh(FS_J)
  t2.cmd()
  assert(hook(t2)("c"))
  assert(hook(t2)("down"))
  eq("J2b down assume 2o resultado", curitem(t2.vim.holds[#t2.vim.holds]), "docs.txt")
  assert(hook(t2)("enter"))
  eq("J2c enter sem callback: nada roda", #t2.termux.runs, 0)

  -- J3 limpar o filtro volta para a lista do diretório
  local t3 = fresh(FS_J)
  t3.cmd()
  assert(hook(t3)("c"))
  assert(hook(t3)("back"))
  eq("J3 volta ao dir list", head(t3.vim.holds[#t3.vim.holds]), "fzf 2/5  @~")
end

do
  -- J4 busca do home inteiro mesmo dentro de subpasta
  local t = fresh(FS_J)
  t.cmd()
  assert(hook(t)("enter")) -- storage/
  assert(hook(t)("c"))
  eq("J4 dentro de storage ainda busca ~", t.termux.calls[3], findf())
  eq("J4b header @~ (nao @~/storage)", head(t.vim.holds[#t.vim.holds]), "fzf 1/2  @~  'c'")
end

do
  -- J5 busca sem match mantem sessao e esc continua limpando
  local t = fresh(FS_J)
  t.cmd()
  assert(hook(t)("z"))
  assert(hook(t)("z"))
  eq("J5 sem match header", head(t.vim.holds[#t.vim.holds]), "fzf 0/0  @~  'zz'")
  assert(hook(t)("esc"))
  eq("J5b esc limpa e volta ao dir list", head(t.vim.holds[#t.vim.holds]), "fzf 2/5  @~")
end

do
  -- J6 letra j dispara a busca (deseleciona a navegacao)
  local t = fresh(FS_J)
  t.cmd()
  assert(hook(t)("j"))
  eq("J6 'j' busca no home", head(t.vim.holds[#t.vim.holds]), "fzf 1/1  @~  'j'")
  eq("J6b resultado do j", jl(t.vim.holds[#t.vim.holds]), "> jogo.dat")
end

do
  -- J7 indice construido uma unica vez por sessao (find nao repete por tecla)
  local t = fresh(FS_J)
  t.cmd()
  assert(hook(t)("c"))
  assert(hook(t)("back"))
  assert(hook(t)("j"))
  assert(hook(t)("back"))
  assert(hook(t)("d"))
  eq("J7 find chamado uma vez (2 execs: cold-start, find)", #t.termux.calls, 2)
  eq("J7b ultima busca filtrou do indice", head(t.vim.holds[#t.vim.holds]), "fzf 1/2  @~  'd'")
end

do
  -- J8 indice assincrono: teclado nunca trava enquanto o find sobe
  local t = fresh(FS_J, { defer_async = true })
  t.cmd()
  assert(hook(t)("c"))
  eq("J8 enquanto indexa: placeholder", head(t.vim.holds[#t.vim.holds]), "fzf 0/0  @~  'c'")
  assert(hook(t)("a"))
  eq("J8b sem novo find (1 chamada), teclado segue vivo", (function()
    local f = 0
    for _, c in ipairs(t.termux.calls) do if c == findf() then f = f + 1 end end
    return f
  end)(), 1)
  eq("J8c query acumula durante o index", head(t.vim.holds[#t.vim.holds]), "fzf 0/0  @~  'ca'")
  t.termux.pending[1].cb(FS_J[findf()])
  eq("J8d resultado do query acumulado", head(t.vim.holds[#t.vim.holds]), "fzf 1/1  @~  'ca'")
  eq("J8e linha do resultado", jl(t.vim.holds[#t.vim.holds]), "> ~storage/calc.txt")
end

do
  -- J9 descida assincrona: 'carregando...' enquanto o ls volta, teclado ativo
  local t = fresh(FS_D, { defer_async = true })
  t.cmd()
  assert(hook(t)("enter"))
  eq("J9 descida pendente: carregando", head(t.vim.holds[#t.vim.holds]), "fzf: carregando...")
  eq("J9b ls requisitado (deferido)", t.termux.pending[1].c, ls(HOME .. "/storage/"))
  eq("J9c seta e consumida durante pendencia", hook(t)("down"), true)
  t.termux.pending[1].cb(FS_D[ls(HOME .. "/storage/")])
  eq("J9d lista chega apos o ls", head(t.vim.holds[#t.vim.holds]), "fzf 2/4  @~/storage/")
end

do
  -- J10 resultado aninhado mostra so a pasta imediata ("~c/arq.txt")
  local FS_N = {
    [homef()] = HOME .. "\n" .. "a/\n",
    [findf()] = HOME .. "/a/b/c/arq.txt",
  }
  local t = fresh(FS_N)
  t.cmd()
  assert(hook(t)("a"))
  eq("J10 pasta imediata + arquivo", head(t.vim.holds[#t.vim.holds]), "fzf 1/1  @~  'a'")
  eq("J10b linha aninhada", jl(t.vim.holds[#t.vim.holds]), "> ~c/arq.txt")
end

do
  -- J11 arquivos ocultos entram no indice ('.' nao e mais podado)
  local FS_H = {
    [homef()] = HOME .. "\n" .. "storage/\n",
    [findf()] = HOME .. "/.bashrc\n" .. HOME .. "/storage/.secret.cfg",
  }
  local t = fresh(FS_H)
  t.cmd()
  for _, c in ipairs { "b", "a", "s", "h" } do assert(hook(t)(c)) end
  eq("J11 oculto na raiz", head(t.vim.holds[#t.vim.holds]), "fzf 1/1  @~  'bash'")
  eq("J11b linha", jl(t.vim.holds[#t.vim.holds]), "> .bashrc")
  for _ = 1, 4 do assert(hook(t)("back")) end
  for _, c in ipairs { ".", "s", "e", "c", "r", "e", "t" } do assert(hook(t)(c)) end
  eq("J11c oculto em subpasta", head(t.vim.holds[#t.vim.holds]), "fzf 1/1  @~  '.secret'")
  eq("J11d linha", jl(t.vim.holds[#t.vim.holds]), "> ~storage/.secret.cfg")
end

-----------------------------------------------------------------------
print("== K. Modo seletor (open_explorer c/ callback) ==")

do
  -- K1 seletor estilo open_explorer: navega ate um arquivo e o callback recebe ele
  local t = fresh(FS_D)
  local picked = {}
  t.mod.open_explorer(nil, function(p) picked[1] = p end)
  assert(hook(t)("enter"))                 -- storage/
  assert(hook(t)("down"))                  -- storage.png
  assert(hook(t)("down"))                  -- docs/
  assert(hook(t)("enter"))                 -- entra docs/
  assert(hook(t)("enter"))                 -- readme (cur=2)
  eq("K1 seleciona arquivo", picked[1], HOME .. "/storage/docs/readme.md")
  eq("K1b nao roda comando", #t.termux.runs, 0)
  eq("K1c sai p/ insert", t.vim.modes[#t.vim.modes], "insert")

  -- K2 pasta: callback NAO e chamado, continua navegando
  local t2 = fresh(FS_D)
  local n = 0
  t2.mod.open_explorer(nil, function() n = n + 1 end)
  assert(hook(t2)("enter"))                -- storage/
  eq("K2 pasta so navega (sem callback)", n, 0)
  assert(hook(t2)("esc"))
  eq("K2b esc sai sem chamar", n, 0)

  -- K3 esc descarta o callback: sessao nova (sem picker) nao roda NADA
  t2.cmd()
  assert(hook(t2)("enter"))                -- storage/
  assert(hook(t2)("down"))
  assert(hook(t2)("down"))
  assert(hook(t2)("enter"))                -- docs/
  assert(hook(t2)("enter"))                -- readme
  ok("K3 sessao nova (sem callback) nao roda", #t2.termux.runs == 0)
  eq("K3b callback velho nunca chamou", n, 0)

  -- K4 run() c/ callback = seletor de linha: Enter entrega a linha escolhida
  local t4 = fresh({ ["pkg list-installed"] = "alsa-utils\nzip\nzsh" })
  local picked = {}
  t4.mod.run({ "pkg", "list-installed" }, function(line) picked[1] = line end)
  eq("K4 header 'enter roda' so com callback", head(t4.vim.holds[#t4.vim.holds]), "fzf 1/3  enter roda")
  assert(hook(t4)("down"))
  assert(hook(t4)("enter"))
  eq("K4b linha entregue por callback", picked[1], "zip")
  eq("K4c e nada roda", #t4.termux.runs, 0)
end

-----------------------------------------------------------------------
print(string.rep("-", 40))
print(string.format("Passou: %d   Falhou: %d", pass, fail))
if fail > 0 then
  print("Falhas:")
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
print("SUITE OK")
os.exit(0)

