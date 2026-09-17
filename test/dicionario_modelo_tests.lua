-- dicionario_modelo_tests.lua — mini-modelo de contexto do :dict.
-- Rode:  lua5.1 test/dicionario_modelo_tests.lua   (sai 0 = ok, 1 = falhas)
-- Cobre: parse do n-grama (B/T), p_ctx c/ backoff, completar prefixo com
-- confiança extra-alta ("caf" -> "café", nunca "cá") e desempate por contexto
-- no fuzzy ("ela queria bato" pende para o candidato que o modelo apoia).
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

-- Índice embutido real (cacheado) p/ os testes de âncora de regressão.
local embutido_cache
local function embutido()
  if embutido_cache == nil then
    local ok, chunk = pcall(loadfile, "plugins/dicionario_dados.lua")
    embutido_cache = ok and chunk and chunk() or false
  end
  return embutido_cache
end

-- Modelo embutido real (cacheado) p/ validar o loader.
local modelo_cache
local function modelo_embutido()
  if modelo_cache == nil then
    local ok, chunk = pcall(loadfile, "plugins/dicionario_modelo.lua")
    modelo_cache = ok and chunk and chunk() or nil
  end
  return modelo_cache
end

-- Mocks de vim + carrega o plugin num ambiente isolado (como dicionario_tests).
local function fresh()
  local vim
  vim = {
    regs = {}, statuses = {}, replaces = {}, text = "",
    handle = 0, interval_fn = nil,
    register = function(n, f) vim.regs[#vim.regs + 1] = { n, f } end,
    status = function() end, status_hold = function() end,
    interval = function(ms, fn) vim.handle = vim.handle + 1; vim.interval_fn = fn; return vim.handle end,
    clear_interval = function() vim.interval_fn = nil end,
    get_text = function() return vim.text end,
    get_sel = function() return #vim.text, #vim.text end,
    replace = function() end, send = function() end, set_sel = function() end,
    set_mode = function() end, page = function() end, key_hook = function() end,
  }
  local env = { vim = vim }
  env.require = function(name)
    if name == "termux" then return { run = function() end, exec = function() end } end
    if name == "shell" then return { shq = function(s) return s end } end
    if name == "dicionario_dados" then return embutido() end
    if name == "dicionario_modelo" then return modelo_embutido() end
  end
  setmetatable(env, { __index = _G })
  local chunk = assert(loadfile(PLUGIN))
  setfenv(chunk, env)
  local mod = assert(chunk(), "plugin carrega")
  return { vim = vim, mod = mod }
end

local F = fresh().mod
local d = nil -- índice ciado por bloco

-- ============ A. _construir_modelo parseia B e T ============
do
  local m = F._construir_modelo(
    "Bela\t10\tbata:6\tbatu:4\n" ..
    "Bcidade\t20\testado:5\tvida:15\n" ..
    "Tela queria\t12\tbata:9\tbatu:1\n")
  eq("A. bigrama lido", m.B["ela"]["bata"], 6)
  eq("A. bigrama soma", m.somaB["ela"], 10)
  eq("A. trigrama lido", m.T["ela queria"]["batu"], 1)
  eq("A. trigrama soma", m.somaT["ela queria"], 12)
  local m2 = F._construir_modelo("")
  eq("A. vazio nao quebra", (m2.B and next(m2.B) == nil), true)
end

-- ============ B. p_ctx: bigrama, trigrama e backoff ============
do
  local m = F._construir_modelo(
    "Bela\t10\tbata:6\tbatu:4\n" ..
    "Tela queria\t12\tbata:9\tbatu:1\n")
  eq("B. bigrama", F.p_ctx(m, nil, "ela", "bata"), 0.6)
  eq("B. trigrama tem precedencia", F.p_ctx(m, "ela", "queria", "bata"), 9 / 12)
  eq("B. alvo fora -> nil", F.p_ctx(m, nil, "ela", "zzz"), nil)
  eq("B. ctx fora -> nil", F.p_ctx(m, nil, "zzz", "bata"), nil)
  eq("B. sem modelo -> nil", F.p_ctx(nil, nil, "ela", "bata"), nil)
end

-- ============ C. completar prefixo: confiança extra-alta ============
-- "ca" (freq 102k) é +comum que "cafe" (26k); sem o sinal de prefixo o fuzzy
-- daria "cá". Com o prefixo único e comum, "'caf' -> 'café'".
do
  d = F.dados_de_linhas({
    "ca\tcá\t775\t102713",
    "cafe\tcafé\t196\t26148",
    "cafeina\tcafeína\t0\t615",
    "con\tcon\t621\t0",
  })
  eq("C. caf -> café (nunca cá)", F.corrigir_palavra(d, "caf"), "café")
  eq("C. caf c/ contexto segue café", F.corrigir_palavra(d, "caf", "uma", "em"), "café")
  eq("C. con (exato) preservado", F.corrigir_palavra(d, "con"), nil)
  eq("C. chave de 2 letras ignorada", F.corrigir_palavra(d, "ca"), nil)
  eq("C. cafe exato ainda corrige acento", F.corrigir_palavra(d, "cafe"), "café")
end

-- ============ C2. prefixo: freq abaixo do teto não "completa" ============
do
  local d2 = F.dados_de_linhas({
    "ca\tcá\t775\t102713",
    "cafe\tcafé\t196\t400", -- comum demais? não: abaixo de prefixo_freq_min
  })
  eq("C2. prefixo raro nao completa (volta pras modas)", F.corrigir_palavra(d2, "caf"), "cá")
end

-- ============ C3. prefixo ambíguo (2 comuns) não "completa" ============
do
  local d3 = F.dados_de_linhas({
    "face\tface\t0\t26148",
    "faca\tfaca\t0\t25000",
    "faz\tfaz\t900000\t0",
  })
  -- Face e faca são completamentos comuns ao mesmo tempo -> não força a dedo;
  -- o fuzzy segue e "fac" também compete com "faz" a 1 de distância -> a moda
  -- (faz, 900k) decide. O importante é NÃO virar "faca"/"face" arbitrário.
  eq("C3. fac ambiguo nao completa a dedo", F.corrigir_palavra(d3, "fac"), "faz")
end

-- ============ D. desempate por contexto no fuzzy ============
-- "bato" tem a mesma distância p/ "bata" e "batu" (DL 1). Sem modelo vence a
-- moda (bata); com o bigrama "ela" apoiando batu, vence batu.
do
  local LINHAS = { "bata\tbata\t10\t0", "batu\tbatu\t8\t0" }
  local dD = F.dados_de_linhas(LINHAS)
  eq("D. sem contexto vence a moda", F.corrigir_palavra(dD, "bato"), "bata")

  dD.modelo = F._construir_modelo("Bela\t10\tbata:2\tbatu:8\n")
  eq("D. bigrama puxa p/ batu", F.corrigir_palavra(dD, "bato", "ela"), "batu")
  eq("D. ctx desconhecido nao muda", F.corrigir_palavra(dD, "bato", "zzz"), "bata")

  -- trigrama tem precedência sobre o bigrama
  dD.modelo = F._construir_modelo(
    "Bela\t10\tbata:2\tbatu:8\n" ..
    "Tela queria\t12\tbata:9\tbatu:1\n")
  eq("D. trigrama prevalece", F.corrigir_palavra(dD, "bato", "queria", "ela"), "bata")
end

-- ============ E. custo de edição (QWERTY) ============
do
  eq("E. substituicao vizinha 0.6", F.custo_edicao("abc", "abx"), 0.6)
  eq("E. transposicao 0.7", F.custo_edicao("ab", "ba"), 0.7)
  eq("E. insercao 1.0", F.custo_edicao("abc", "abxc"), 1.0)
  eq("E. igual 0", F.custo_edicao("abc", "abc"), 0)
end

-- ============ F. âncoras de regressão no índice REAL ============
do
  local dR = F.carregar_embutido()
  assert(dR, "indice embutido carrega")
  eq("F. caf -> café", F.corrigir_palavra(dR, "caf"), "café")
  eq("F. palvra -> palavra", F.corrigir_palavra(dR, "palvra"), "palavra")
  eq("F. dvoi -> dói", F.corrigir_palavra(dR, "dvoi"), "dói")
  eq("F. paa -> para", F.corrigir_palavra(dR, "paa"), "para")
  eq("F. voce -> você", F.corrigir_palavra(dR, "voce"), "você")
  eq("F. con preservado", F.corrigir_palavra(dR, "con"), nil)
  eq("F. teclado preservado", F.corrigir_palavra(dR, "teclado"), nil)
  eq("F. cam preservado", F.corrigir_palavra(dR, "cam"), nil)
  eq("F. acentuacao -> acentuação", F.corrigir_palavra(dR, "acentuacao"), "acentuação")
end

-- ============ H. modo só-modelo: regras determinísticas fora ============
-- Por padrão (regras) esta/tem/fabrica/porem são preservadas. Com :dict modo
-- ligado nada trava: a canônica (moda/modelo) manda. O vocabulário continua
-- sendo o índice (não dá pra corrigir sem ele).
do
  local dH = F.dados_de_linhas({
    "esta\testá\t272722\t1335658",
    "porem\tporém\t30000\t120000",
    "tem\ttem\t442806\t91968",
  })
  eq("H. regras: esta preservada", F.corrigir_palavra(dH, "esta"), nil)
  eq("H. regras: tem preservado", F.corrigir_palavra(dH, "tem"), nil)
  eq("H. regras: porem preservado", F.corrigir_palavra(dH, "porem"), nil)
  F.setup({ modo_modelo = true })
  eq("H. so-modelo: esta -> está", F.corrigir_palavra(dH, "esta"), "está")
  eq("H. so-modelo: porem -> porém", F.corrigir_palavra(dH, "porem"), "porém")
  eq("H. canônica já é a plana -> nada (tem==tem)", F.corrigir_palavra(dH, "tem"), nil)
  eq("H. acento digitado nunca rebaixado", F.corrigir_palavra(dH, "pôr"), nil)
  eq("H. ja acentuada nada a fazer", F.corrigir_palavra(dH, "está"), nil)
  F.setup()
  eq("H. reset volta a preservar", F.corrigir_palavra(dH, "esta"), nil)
end

-- ============ Sanidade do loader embutido do modelo ============
do
  local m = F.carregar_modelo_embutido()
  eq("G. modelo embutido carrega", m ~= nil, true)
  if m then
    local nt = 0
    for _ in pairs(m.T) do nt = nt + 1 end
    eq("G. tem trigramas", nt > 0, true)
  end
end

-- ============ I. flips do acentua_regras.py (curadoria regras+corpus) ======
-- As 26 canônicas enriquecidas: em modo regras só corrigem quando a PLANTA
-- não é palavra real (fp 0 no corpus); com "fp" presente a forma plana é
-- preservada. Homógrafos não-flipados (manga, trocos, valeria) ficam intactos.
do
  local dI = F.dados_de_linhas({
    "canon\tcânon\t6\t10",
    "esporadico\tesporádico\t0\t3",
    "ibis\tíbis\t0\t5",
    "kaka\tkaká\t0\t3",
  })
  eq("I. regras: espadico (fp 0) corrige", F.corrigir_palavra(dI, "esporadico"), "esporádico")
  eq("I. regras: ibis (fp 0) corrige", F.corrigir_palavra(dI, "ibis"), "íbis")
  eq("I. regras: canon tem plana real -> preserva", F.corrigir_palavra(dI, "canon"), nil)
  eq("I. regras: kaka (fp 0) corrige", F.corrigir_palavra(dI, "kaka"), "kaká")
  F.setup({ modo_modelo = true })
  eq("I. so-modelo: esporadico", F.corrigir_palavra(dI, "esporadico"), "esporádico")
  eq("I. so-modelo: canon -> cânon", F.corrigir_palavra(dI, "canon"), "cânon")
  F.setup()
end

-- ============ J. homógrafos NÃO flipados pelo acentua_regras.py ======
-- manga (fruta/manga de camisa), trocos (mudança) e valeria (verbo) continuam
-- com a canônica plana: corrigir em cima deles seria trocar por palavra errada.
do
  local dJ = F.dados_de_linhas({
    "manga\tmanga\t1364\t0",
    "trocos\ttrocos\t1208\t0",
    "valeria\tvaleria\t373\t0",
  })
  eq("J. regras: manga preservada", F.corrigir_palavra(dJ, "manga"), nil)
  eq("J. regras: trocos preservado", F.corrigir_palavra(dJ, "trocos"), nil)
  eq("J. regras: valeria preservada", F.corrigir_palavra(dJ, "valeria"), nil)
  F.setup({ modo_modelo = true })
  eq("J. so-modelo: manga continua plana", F.corrigir_palavra(dJ, "manga"), nil)
  eq("J. so-modelo: trocos continua plana", F.corrigir_palavra(dJ, "trocos"), nil)
  F.setup()
end

print(string.format("dicionario_modelo: Passou: %d   Falhou: %d", pass, fail))
for i = 1, #failures do print("  - " .. failures[i]) end
os.exit(fail == 0 and 0 or 1)