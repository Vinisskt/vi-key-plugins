-- dicionario_tests.lua — cobertura do plugin dicionario (:dict).
-- Rode:  lua5.1 test/dicionario_tests.lua   (sai 0 = ok, 1 = falhas)
-- O módulo é carregado num ambiente isolado (setfenv) com mocks de vim, para
-- o estado (intervalo, registros, texto) nunca vazar entre cenários.
local PLUGIN = "plugins/dicionario.lua"

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

local function eq(name, obtive, quero)
  ok(name .. (obtive == quero and "" or
      (" (obtive <" .. tostring(obtive) .. ">, quero <" .. tostring(quero) .. ">)")),
      obtive == quero)
end

-- dicionario_dados.lua — índice embutido (carregado uma vez, cacheado).
local embutido_cache
local function embutido()
  if embutido_cache == nil then
    local ok, chunk = pcall(loadfile, "plugins/dicionario_dados.lua")
    embutido_cache = ok and chunk and chunk() or false
  end
  return embutido_cache
end

-- Cria ambiente + mocks e carrega o plugin.
local function fresh()
  local vim
  vim = {
    regs = {}, statuses = {}, replaces = {}, text = "",
    handle = 0, interval_fn = nil,
    register = function(n, f) vim.regs[#vim.regs + 1] = { n, f } end,
    status = function(s) vim.statuses[#vim.statuses + 1] = s end,
    status_hold = function() end,
    interval = function(ms, fn) vim.handle = vim.handle + 1; vim.interval_fn = fn; return vim.handle end,
    clear_interval = function() vim.interval_fn = nil end,
    get_text = function() return vim.text end,
    get_sel = function() return #vim.text, #vim.text end,
    replace = function(s, e, t) vim.replaces[#vim.replaces + 1] = { s, e, t } end,
    send = function() end, set_sel = function() end, set_mode = function() end,
    page = function() end, key_hook = function() end,
  }
  local env = { vim = vim }
  env.require = function(name)
    if name == "termux" then return { run = function() end, exec = function() end } end
    if name == "shell" then return { shq = function(s) return s end } end
    if name == "dicionario_dados" then return embutido() end
  end
  setmetatable(env, { __index = _G })
  local chunk = assert(loadfile(PLUGIN))
  setfenv(chunk, env)
  local mod = assert(chunk(), "plugin carrega")
  -- get_sel do app devolve o caret em unidades UTF-16 (não bytes).
  vim.get_sel = function() return mod.unidades_utf16(vim.text), mod.unidades_utf16(vim.text) end
  local reg = vim.regs[1]
  assert(reg and reg[1] == "dict" and type(reg[2]) == "function", "vim.register(dict, fn)")
  return { vim = vim, mod = mod, cmd = reg[2] }
end

-- ===== Fixture (linhas já ordenadas por chave) =====
local LINHAS = {
  "cafe\tcafé", "casa", "computador", "correu", "correr", "direto",
  "faca", "mais", "nao\tnão", "procurar", "trabalho", "voce\tvocê",
}

-- ================= A. sem_acento =================
do
  local F = fresh().mod
  eq("A. café -> cafe", F.sem_acento("café"), "cafe")
  eq("A. VOCÊ -> voce", F.sem_acento("VOCÊ"), "voce")
  eq("A. frase", F.sem_acento("não são feriado"), "nao sao feriado")
  eq("A. Çà -> ca", F.sem_acento("Çà"), "ca")
  eq("A. sem acento fica igual", F.sem_acento("casa"), "casa")
end

-- ================= B. erro_permitido (regra dos 70%) =================
do
  local F = fresh().mod
  eq("B. len3 -> 1", F.erro_permitido(3), 1)
  eq("B. len6 -> 1", F.erro_permitido(6), 1)
  eq("B. len7 -> 2", F.erro_permitido(7), 2)
  eq("B. len10 -> 3", F.erro_permitido(10), 3)
end

-- ================= C. índice + busca binária por prefixo =================
do
  local F = fresh().mod
  local d = F.dados_de_linhas(LINHAS)
  eq("C. n de linhas", d.n, 12)
  local l, h = F.intervalo_por_prefixo(d, 1, d.n, "ca")
  eq("C. 'ca' tem 2 candidatos", h - l + 1, 2)
  local l2, h2 = F.intervalo_por_prefixo(d, 1, d.n, "cor")
  eq("C. 'cor' tem 2 candidatos", h2 - l2 + 1, 2)
  local l3, h3 = F.intervalo_por_prefixo(d, 1, d.n, "xxx")
  eq("C. prefixo inexistente -> vazio", l3 > h3, true)
  local l4, h4 = F.intervalo_por_prefixo(d, 1, d.n, "voce")
  eq("C. 'voce' casou 1", (h4 - l4 + 1) == 1, true)
end

-- ================= D. halving incremental =================
do
  local F = fresh().mod
  local d = F.dados_de_linhas(LINHAS)
  local l0, h0 = F.intervalo_por_prefixo(d, 1, d.n, "vo")
  local l1, h1 = F.intervalo_por_prefixo(d, l0, h0, "voc")
  local L1, H1 = F.intervalo_por_prefixo(d, 1, d.n, "voc")
  eq("D. estreitar dentro da faixa = busca completa", (l1 == L1 and h1 == H1), true)
  eq("D. faixa inicial 'vo' >= 'voc'", (h0 - l0 + 1) >= (h1 - l1 + 1), true)
end

-- ================= E. correção: acentos (casa exata) =================
do
  local F = fresh().mod
  local d = F.dados_de_linhas(LINHAS)
  eq("E. voce -> você", F.corrigir_palavra(d, "voce"), "você")
  eq("E. nao -> não", F.corrigir_palavra(d, "nao"), "não")
  eq("E. já acentuada -> nada", F.corrigir_palavra(d, "você"), nil)
  eq("E. desconhecida -> nada", F.corrigir_palavra(d, "xyz"), nil)
end

-- ============ E2. grafias reais e comuns são preservadas (freq) ============
-- Formato real do índice: "chave\tcanonical\tfreq_plana\tfreq_acentuada".
do
  local F = fresh().mod
  local LINHAS2 = {
    "atras\tatrás\t0\t12345", "esta\testá\t272722\t1335658",
    "ideia\tideia\t71498\t6403", "nao\tnão\t20377\t4754253",
    "que\tque\t5984819\t213969", "tem\ttem\t442806\t91968",
    "voce\tvocê\t6261\t395629",
  }
  local d = F.dados_de_linhas(LINHAS2)
  eq("E2. esta (comum) não vira está", F.corrigir_palavra(d, "esta"), nil)
  eq("E2. está já certa", F.corrigir_palavra(d, "está"), nil)
  eq("E2. tem (comum) não vira têm", F.corrigir_palavra(d, "tem"), nil)
  eq("E2. têm já certa", F.corrigir_palavra(d, "têm"), nil)
  eq("E2. que não vira quê", F.corrigir_palavra(d, "que"), nil)
  eq("E2. quê já certa", F.corrigir_palavra(d, "quê"), nil)
  eq("E2. voce (rara) ainda vira você", F.corrigir_palavra(d, "voce"), "você")
  eq("E2. você já certa", F.corrigir_palavra(d, "você"), nil)
  eq("E2. grafia plana ausente -> corrige", F.corrigir_palavra(d, "atras"), "atrás")
  eq("E2. atrás já certa", F.corrigir_palavra(d, "atrás"), nil)
  eq("E2. idéia (antiga) vira ideia", F.corrigir_palavra(d, "idéia"), "ideia")
  eq("E2. ideia já certa", F.corrigir_palavra(d, "ideia"), nil)
  F.setup({ min_freq_nao_corrige = 0 })
  eq("E2. proteção desligada corrige esta", F.corrigir_palavra(d, "esta"), "está")
  F.setup()
  eq("E2. opção não quebra voce", F.corrigir_palavra(d, "voce"), "você")
end

-- ================= F. regras: min_len e maiúsculas =================
do
  local F = fresh().mod
  local d = F.dados_de_linhas(LINHAS)
  eq("F. curta ignorada", F.corrigir_palavra(d, "é"), nil)
  eq("F. Maiúscula pulada (default)", F.corrigir_palavra(d, "Voce"), nil)
  F.setup({ pular_maiuscula = false })
  eq("F. Maiúscula corrigida c/ opção", F.corrigir_palavra(d, "Voce"), "você")
  F.setup({ min_len = 2 })
  eq("F. len2 aceita c/ min_len=2", F.corrigir_palavra(d, "nao"), "não")
  F.setup()
end

-- ================= G. fuzzy (70%) =================
do
  local F = fresh().mod
  local d = F.dados_de_linhas(LINHAS)
  eq("G. caza -> casa", F.corrigir_palavra(d, "caza"), "casa")
  eq("G. procurra -> procurar", F.corrigir_palavra(d, "procurra"), "procurar")
  eq("G. palavra já certa -> nada", F.corrigir_palavra(d, "faca"), nil)
  eq("G. zerar dist", F.levenshtein("casa", "casa"), 0)
  eq("G. dist 1", F.levenshtein("caza", "casa"), 1)
end

-- ================= H. ultima_palavra (offsets em bytes) =================
do
  local F = fresh().mod
  -- "olá voce " => o l á(2B) _ v o c e _
  local t = "olá voce "
  local w1, w2, p, c = F.ultima_palavra(t, #t)
  eq("H. comitada flag", c, true)
  eq("H. comitada palavra", p, "voce")
  eq("H. comitada wstart1", w1, 6)
  eq("H. comitada wend1", w2, 9)
  -- ainda digitando "olá vo"
  local t2 = "olá vo"
  local a1, a2, ap, ac = F.ultima_palavra(t2, #t2)
  eq("H. digitando word", ap, "vo")
  eq("H. digitando flag", ac, false)
  eq("H. digitando wstart1", a1, 6)
  -- pontuação comita: "olá,"
  local t3 = "olá,"
  local b1, b2, bp, bc = F.ultima_palavra(t3, #t3)
  eq("H. vírgula comita", bc, true)
  eq("H. vírgula palavra", bp, "olá")
  eq("H. vírgula wend1", b2, 4)
end

-- ================= I. watcher (passada) com replace =================
do
  local F = fresh()
  local vim, mod = F.vim, F.mod
  mod.ponha_dados(mod.dados_de_linhas(LINHAS))
  vim.text = "olá voce "
  mod.passada()
  eq("I. replace chamado 1x", #vim.replaces, 1)
  local r = vim.replaces[1]
  eq("I. replace início (unidades UTF-16)", r[1], 4)
  eq("I. replace fim inclui o espaço", r[2], 9)
  eq("I. replace texto c/ espaço", r[3], "você ")
  eq("I. status avisou", #vim.statuses >= 1, true)
end

do
  -- com ENTER ("\n" como o teclado envia): substitui e mantém o enter
  local F = fresh()
  local vim, mod = F.vim, F.mod
  mod.ponha_dados(mod.dados_de_linhas(LINHAS))
  vim.text = "olá voce\n"
  mod.passada()
  eq("I. enter corrige", #vim.replaces, 1)
  if vim.replaces[1] then
    eq("I. enter range", vim.replaces[1][1] .. "," .. vim.replaces[1][2], "4,9")
    eq("I. enter texto c/ \\n", vim.replaces[1][3], "você\n")
  end
end

do
  -- palavra no início do texto (p0 == 0) e o dedup depois
  local F = fresh()
  local vim, mod = F.vim, F.mod
  mod.ponha_dados(mod.dados_de_linhas(LINHAS))
  vim.text = "voce "
  mod.passada()
  eq("I. p0 == 0", #vim.replaces, 1)
  if vim.replaces[1] then
    eq("I. p0/fim", vim.replaces[1][1] .. "," .. vim.replaces[1][2], "0,5")
    eq("I. texto", vim.replaces[1][3], "você ")
  end
  vim.replaces = {}
  mod.passada()
  eq("I. sem repetir", #vim.replaces, 0)
  F.cmd("off")
  vim.text = "nao "
  mod.passada()
  eq("I. off não corrige", #vim.replaces, 0)
  F.cmd("on")
end

-- ================= J. intervalo configurável =================
do
  local F = fresh()
  local mod = F.mod
  eq("J. defaults ativado", mod.get_config().ativado, true)
  mod.setup({ intervalo_ms = 120, min_len = 4 })
  local cfg = mod.get_config()
  eq("J. intervalo aplicado", cfg.intervalo_ms, 120)
  eq("J. min_len aplicado", cfg.min_len, 4)
  mod.setup()
end

-- ================= K. módulo embutido (offline, índice real) =================
do
  local e = embutido()
  eq("K. embutido é string", type(e), "string")
  eq("K. embutido com \t", e:find("\t", 1, true) ~= nil, true)
  eq("K. embutido contém você", e:find("voce\tvocê", 1, true) ~= nil, true)
  eq("K. embutido é grande", #e > 200000, true)
end

do
  -- passada SEM ponha_dados: usa o dicionário embutido via require (sem io)
  local F = fresh()
  local vim, mod = F.vim, F.mod
  vim.text = "olá voce "
  mod.passada()
  eq("K. carrega embutido e corrige", #vim.replaces, 1)
  if vim.replaces[1] then
    eq("K. texto c/ espaço", vim.replaces[1][3], "você ")
  end
  -- correção de palavra inexistente no índice real
  vim.replaces = {}
  vim.text = "olá zkxqv "
  mod.passada()
  eq("K. desconhecida não edita", #vim.replaces, 0)
  -- comandos com o índice real carregado
  F.cmd("nao")
  eq("K. :dict nao -> não", vim.statuses[#vim.statuses], "dicionário: nao → não")
  F.cmd("xyzqwe")
  eq("K. :dict xyzqwe nada", vim.statuses[#vim.statuses],
    "dicionário: 'xyzqwe' nada a corrigir")
end

-- ================= resumo =================
print("Passou: " .. pass .. "   Falhou: " .. fail)
if fail > 0 then
  os.exit(1)
end