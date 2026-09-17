-- bench_whatsapp.lua — simulação de conversa de WhatsApp (pt-BR, sem acento +
-- errinhos) medindo o :dict nos dois modos com o índice/modelo REAIS embutidos.
-- Rode: lua5.1 test/bench_whatsapp.lua   (sai 0; imprime a medição)
--
-- "certo" = a canônica devolvida é uma palavra do dicionário (o própio :dict
-- devolveria nil ao tentar corrigir de novo => grafia estável). "troca errada"
-- = devolveu grafia que o próprio :dict rejeitaria/corrigiria de volta —
-- exatamente o bug "manga -> mangá".

local embutido_cache
local function embutido()
  if embutido_cache == nil then
    local ok, chunk = pcall(loadfile, "plugins/dicionario_dados.lua")
    embutido_cache = ok and chunk and chunk() or false
  end
  return embutido_cache
end
local modelo_cache
local function modelo_embutido()
  if modelo_cache == nil then
    local ok, chunk = pcall(loadfile, "plugins/dicionario_modelo.lua")
    modelo_cache = ok and chunk and chunk() or nil
  end
  return modelo_cache
end

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
  local chunk = assert(loadfile("plugins/dicionario.lua"))
  setfenv(chunk, env)
  local mod = assert(chunk(), "plugin carrega")
  local d = assert(mod.carregar_embutido(), "índice embutido")
  assert(mod.carregar_modelo_embutido(), "modelo embutido")
  return { vim = vim, mod = mod, d = d }
end

local F = fresh()

local function sem_acento(p)
  local out, n = {}, 0
  local BASE = { ["ç"] = "c", ["Ç"] = "C", ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
                 ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
                 ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u" }
  for i = 1, #p do
    local b = p:byte(i)
    if b >= 0xC2 then
      out[#out + 1] = BASE[p:sub(i, i + 1)] or p:sub(i, i + 1)
      n = n + 1
    else
      out[#out + 1] = p:sub(i, i)
      n = n + 1
    end
  end
  return table.concat(out)
end

local conversa = {
  "voce ja chegou em casa?",
  "nao, to chegando agora",
  "a gente ia se ve mais tarde",
  "pode ser que eu va na festa",
  "eu nao sabia que voce tinha ido",
  "tudo bem, so queria saber",
  "posso te passar o numero?",
  "claro, pode mandar",
  "que horas voce vai sair?",
  "um pouco antes do almoco",
  "voce ja leu o livro que eu falei?",
  "ainda nao, mas vou comecar hoje",
  "ele disse que vai chover amanha",
  "a gente pode marcar para sexta",
  "voce prefere cafe ou cha?",
  "prefiro cafe, mas hoje to tomando cha",
  "ontem eu vi aquele filme novo",
  "foi bom? nao vi ainda",
  "manda foto da festa depois",
  "vou mandar sim, so deixa eu encontrar",
  "essa musica e muito boa",
  "qual e o nome do cantor?",
  "e o caetano, voce conhece?",
  "claro que conheco, ele e genio",
  "a gente se fala mais tarde entao",
  "combinado, bom descanso!",
  "fala comigo quando chegar",
  "beijo, ate mais!",
  -- homógrafas "fabrica/fábrica" com contexto: verbo (preserva) vs
  -- substantivo (acentua) — o caso que a janela longa resolve.
  "ele fabrica brinquedos",
  "a fabrica fechou",
  "ela fabrica pneus na fabrica antiga",
}

local function corrige_frase(modo, frase)
  F.mod.setup({ modo_modelo = (modo == "modelo") })
  local digitada = sem_acento(frase)
  local toks = {}
  for tok in digitada:gmatch("[A-Za-zÀ-ÿçÇ']+") do toks[#toks + 1] = tok end
  local antes, antes2 = nil, nil
  -- Janela: últimas N palavras do TEXTO já digitado até aqui (mais recente 1º).
  -- Passada para o 5º arg da assinatura nova; nil = caminho antigo (2 antes).
  local janela = {}
  local out, d2 = {}, {}
  for i, t in ipairs(toks) do
    local r = F.mod.corrigir_palavra(F.d, t, antes, antes2, janela)
    out[i], d2[i] = r, r and F.mod.corrigir_palavra(F.d, r, antes, antes2, janela)
    -- empurra a PALAVRA DIGITADA (a grafia real) pra frente da janela
    table.insert(janela, 1, t)
    while #janela > 5 do table.remove(janela) end
    antes2, antes = antes, t
  end
  return toks, out, d2
end

for _, modo in ipairs({ "regras", "modelo" }) do
  local corrigiu, acertou_acento, preservou, troca_errada, aclarou = 0, 0, 0, 0, 0
  local totais_palavras = 0
  print("===== modo " .. modo .. " =====")
  for _, fr in ipairs(conversa) do
    local toks, outs, d2 = corrige_frase(modo, fr)
    local linha = {}
    for i, t in ipairs(toks) do
      totais_palavras = totais_palavras + 1
      local r, r2 = outs[i], d2[i]
      if r == nil then
        preservou = preservou + 1
        linha[#linha + 1] = "·" .. t
      elseif r2 == nil then
        corrigiu = corrigiu + 1
        linha[#linha + 1] = r   -- estável (palavra do dic)
      else
        troca_errada = troca_errada + 1
        linha[#linha + 1] = "!!" .. r .. "!!"
      end
    end
    print("  " .. table.concat(linha, " "))
  end
  print(string.format(
    "  RESUMO %s: palavras=%d  corrigiu=%d  preservou(nil)=%d  troca_errada=%d",
      modo, totais_palavras, corrigiu, preservou, troca_errada))
end
