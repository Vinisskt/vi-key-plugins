-- dicionario.lua — :dict — correção automática de acentos e erros de digitação
-- com um dicionário de Português nativo (baixado e indexado no Termux).
--
-- Não há barra de sugestões: só substitui (vim.replace) a palavra já
-- comitada (espaço/pontuação) quando ela casa com o dicionário com >= 70% de
-- similaridade. Enquanto você digita, o dicionário é "cortado pela metade"
-- com busca binária pelo prefixo já escrito.
--
-- Formas:
--   :dict           estado
--   :dict on|off    liga/desliga a correção automática
--   :dict status    detalhes (caminho, nº de palavras, limites)
--   :dict <palavra> mostra a correção que seria aplicada (não edita nada)
--
-- Dados: plugins/dicionario_dados.lua (embutido, sem download) ou
-- /sdcard/keyboard-lua/data/dicionario/dicionario.dat, gerados por
-- scripts/gera_dicionario.lua a partir de lista de frequência PT.
-- Linhas "chave<TAB>canonical<TAB>freq_plana<TAB>freq_acentuada" ORDENADAS por
-- chave (busca binária). A forma canônica é a de maior frequência — assim
-- "ideia" vence "idéia", "voo" vence "vôo" (ortografia antiga vira ruído).

local M = {}

-- ===== Configuração (padrão das skills: defaults + setup + get_config) =====
local defaults = {
  ativado = true,            -- correção automática ligada por padrão
  intervalo_ms = 350,        -- cadência do "watcher" atrás do texto
  min_len = 3,               -- ignora palavras mais curtas (a, é, só, os...)
  pular_maiuscula = true,    -- não corrige palavras iniciando com MAIÚSCULA
  aviso = true,              -- status curto ao corrigir ("voce → você")
  mostrar_candidatos = false,-- durante a digitação, mostra o nº de candidatos
  min_freq_nao_corrige = 30000, -- grafia digitada com freq >= isso é "forma real
                                -- em uso" e não deve ser trocada (esta, têm, quê)
  dados_dir = "/sdcard/keyboard-lua/data/dicionario",
}
local config = {}
-- Estado do plugin (declarado no topo p/ os closures abaixo capturarem o local).
local dados = nil       -- índice carregado (lazy)
local erro_carregou = "" -- status mostrado uma vez se o arquivo faltar
local handle = nil      -- handle do vim.interval
local intervalo = { prefixo = "", lo = 1, hi = 0 } -- faixa corrente (halving)
local fix = nil         -- último (p0, p1, texto) corrigido, p/ não repetir

local function merge_defs(def, opts)
  opts = opts or {}
  local out = {}
  for k, v in pairs(def) do out[k] = v end
  for k, v in pairs(opts) do out[k] = v end
  return out
end

local function valida(cfg)
  cfg.intervalo_ms = math.max(50, math.floor(tonumber(cfg.intervalo_ms) or 350))
  cfg.min_len = math.max(1, math.floor(tonumber(cfg.min_len) or 3))
  cfg.pular_maiuscula = cfg.pular_maiuscula ~= false
  cfg.ativado = cfg.ativado ~= false
  cfg.dados_dir = tostring(cfg.dados_dir or defaults.dados_dir)
  cfg.min_freq_nao_corrige = math.max(0, math.floor(tonumber(cfg.min_freq_nao_corrige) or 30000))
  for _, k in ipairs({ "aviso", "mostrar_candidatos" }) do
    if type(cfg[k]) ~= "boolean" then cfg[k] = defaults[k] end
  end
  return cfg
end

function M.setup(opts)
  config = valida(merge_defs(defaults, opts))
  return config
end

function M.get_config()
  return config
end

-- ===== Normalização (sem_acento) =====
local ACENTO = {}
for _, p in ipairs({
  { "à", "a" }, { "á", "a" }, { "â", "a" }, { "ã", "a" }, { "ä", "a" }, { "å", "a" },
  { "À", "a" }, { "Á", "a" }, { "Â", "a" }, { "Ã", "a" }, { "Ä", "a" }, { "Å", "a" },
  { "ç", "c" }, { "Ç", "c" },
  { "è", "e" }, { "é", "e" }, { "ê", "e" }, { "ë", "e" },
  { "È", "e" }, { "É", "e" }, { "Ê", "e" }, { "Ë", "e" },
  { "ì", "i" }, { "í", "i" }, { "î", "i" }, { "ï", "i" },
  { "Ì", "i" }, { "Í", "i" }, { "Î", "i" }, { "Ï", "i" },
  { "ñ", "n" }, { "Ñ", "n" },
  { "ò", "o" }, { "ó", "o" }, { "ô", "o" }, { "õ", "o" }, { "ö", "o" },
  { "Ò", "o" }, { "Ó", "o" }, { "Ô", "o" }, { "Õ", "o" }, { "Ö", "o" },
  { "ù", "u" }, { "ú", "u" }, { "û", "u" }, { "ü", "u" },
  { "Ù", "u" }, { "Ú", "u" }, { "Û", "u" }, { "Ü", "u" },
}) do
  ACENTO[p[1]] = p[2]
end

--- "café" -> "cafe"; também normaliza maiúsculas acentuadas.
function M.sem_acento(s)
  -- casa um caractere UTF-8 inteiro por vez (o "." casaria bytes soltos)
  return (s:gsub("([\194-\255][\128-\191]*)",
      function(c) return ACENTO[c] or c end)):lower()
end

local LETRAS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  .. "àáâãäåçèéêëìíîïñòóôõöùûüÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜ"

function M.eh_letra(c)
  if not c or c == "" then return false end
  return LETRAS:find(c, 1, true) ~= nil -- caractere completo (acentos são 2 bytes UTF-8)
end

-- ===== Andar pelos caracteres (offsets do vim são em BYTES) =====
--- Início do caractere que ocupa o byte [p] (volta bytes de continuação).
local function inicio_char(texto, p)
  p = math.max(1, p or 1)
  while p > 1 do
    local b = texto:byte(p)
    if b and b >= 0x80 and b < 0xC0 then p = p - 1 else break end
  end
  return p
end

-- ===== Dados: índice do dicionário em memória =====
-- d = { texto = "<chave>\t<canonical>\n..." , inicio = {offsets das linhas}, n }
-- Só 1 string grande + offsets: memória enxuta, probes são recortes curtos.

function M._construir(texto)
  local inicio, n = {}, 0
  local bp = 1
  while true do
    local p = texto:find("\n", bp, true)
    if not p then break end
    n = n + 1
    inicio[n] = bp
    bp = p + 1
  end
  if n == 0 then return nil end
  return { texto = texto, inicio = inicio, n = n }
end

--- Constrói o índice a partir de uma lista de linhas prontas (testes/fixture).
function M.dados_de_linhas(linhas)
  return M._construir(table.concat(linhas, "\n") .. "\n")
end

function M.carregar(dados_dir)
  local path = dados_dir .. "/dicionario.dat"
  local f = io.open(path, "rb")
  if not f then return nil, "sem " .. path end
  local texto = f:read("*a")
  f:close()
  return M._construir(texto)
end

--- Índice embutido (plugins/dicionario_dados.lua). Requer que o app ache o
--  módulo pelo nome; se o require vier sem rede e falhar, cai no io acima.
function M.carregar_embutido()
  local ok, res = pcall(function() return require("dicionario_dados") end)
  if not ok then return nil, "módulo embutido indisponível" end
  if type(res) ~= "string" or res:find("\t", 1, true) == nil then
    return nil, "módulo embutido inválido"
  end
  return M._construir(res)
end

--- Injeta um índice já pronto (usado pelos testes; pulando o io).
function M.ponha_dados(d)
  dados = d
end

--- Fim (1-based, exclusivo) da linha [i]: hoje num é o byte do "\n".
local function linha_fim(d, i)
  return d.texto:find("\n", d.inicio[i], true) or (d.texto:len() + 1)
end

local function chave_em(d, i)
  local t = d.texto:find("\t", d.inicio[i], true)
  local fim = linha_fim(d, i)
  if t and t < fim then return d.texto:sub(d.inicio[i], t - 1) end
  return d.texto:sub(d.inicio[i], fim - 1) -- sem tab: chave == canonical
end

local function canon_em(d, i)
  local t1 = d.texto:find("\t", d.inicio[i], true)
  local fim = linha_fim(d, i)
  if not t1 or t1 >= fim then return d.texto:sub(d.inicio[i], fim - 1) end
  local t2 = d.texto:find("\t", t1 + 1, true)
  if t2 and t2 < fim then return d.texto:sub(t1 + 1, t2 - 1) end
  return d.texto:sub(t1 + 1, fim - 1) -- "chave\tcanonical" sem frequências
end

--- Frequências da maior grafia PLANTA e da ACENTUADA (0 se a grafia não
--- existir como palavra no corpus). Usadas p/ não "corrigir" grafias reais e
--- comuns (esta, têm, quê...). Linhas antigas sem esse campo retornam 0,0.
local function freqs_em(d, i)
  local fim = linha_fim(d, i)
  local t1 = d.texto:find("\t", d.inicio[i], true)
  local t2 = t1 and d.texto:find("\t", t1 + 1, true)
  if not (t1 and t2 and t2 < fim) then return 0, 0 end
  local fp, fa = d.texto:sub(t2 + 1, fim - 1):match("^(%d+)\t(%d+)$")
  return tonumber(fp) or 0, tonumber(fa) or 0
end

-- ===== Busca binária (cortando o dicionário pela metade) =====
--- Primeiro índice em [lo, hi] com chave >= prefixo.
function M.lower_bound(d, lo, hi, prefixo)
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if chave_em(d, mid) < prefixo then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return lo
end

--- Intervalo inclusivo [lo, hi] das chaves que começam com [prefixo];
--- retorna lo > hi quando não há candidatos. Chaves são só a-z, então o limite
--- superior é a busca binária de prefixo.."{".
function M.intervalo_por_prefixo(d, lo, hi, prefixo)
  local l = M.lower_bound(d, lo, hi, prefixo)
  local h = M.lower_bound(d, l, hi, prefixo .. "{") - 1
  return l, h
end

-- ===== Regra dos 70% =====
--- Erros permitidos p/ o usuário ainda ter acertado >= 70% da palavra.
function M.erro_permitido(n)
  if n < 1 then return 0 end
  return math.max(1, math.floor(n * 0.3))
end

-- Damerau-Levenshtein: transposição de letras adjacentes (erro típico de
-- digitação) custa 1. Só a-z (chaves sem acento), então byte == caractere.
function M.damerau_levenshtein(s, t)
  local n, m = #s, #t
  if n == 0 then return m end
  if m == 0 then return n end
  -- 3 linhas rolantes: d2 = i-2 (p/ transposição), d1 = i-1, d0 = i.
  local d2, d1, d0 = {}, {}, {}
  for j = 0, m do d2[j], d1[j] = j, j end
  for i = 1, n do
    local sb, sprev = s:byte(i), s:byte(i - 1)
    d0[0] = i
    for j = 1, m do
      local cost = (sb == t:byte(j)) and 0 or 1
      local v = math.min(d1[j] + 1, d0[j - 1] + 1, d1[j - 1] + cost)
      if i > 1 and j > 1 and sb == t:byte(j - 1) and sprev == t:byte(j) then
        v = math.min(v, d2[j - 2] + 1)
      end
      d0[j] = v
    end
    d2, d1, d0 = d1, d0, d2
  end
  return d1[m]
end

--- Corrige uma palavra completa. Devolve a forma canônica ou nil.
--  1. casa exata da chave sem acento -> devolve a canônica com acento
--     ("voce" -> "você"); mas se a grafia DIGITADA é uma forma real e comum
--     (frequência >= min_freq_nao_corrige), a palavra é preservada — nunca se
--     troca uma grafia legítima por outra ("esta", "têm", "quê", "é", "à").
--  2. senão, fuzzy: Damerau-Levenshtein <= erros permitidos dentro da faixa
--     do prefixo digitado (relaxando o prefixo em até 3 letras). Empate de
--     distância escolhe a palavra mais frequente (probabilidade unigrama).
--  3. maiúsculas são puladas (nomes próprios), por padrão
function M.corrigir_palavra(d, palavra)
  if not d or type(palavra) ~= "string" then return nil end
  if #palavra < config.min_len then return nil end
  if config.pular_maiuscula and palavra:match("^%u") then return nil end

  local chave = M.sem_acento(palavra)
  local l, h = M.intervalo_por_prefixo(d, 1, d.n, chave)
  if l <= h and chave_em(d, l) == chave then
    local canon = canon_em(d, l)
    if canon ~= palavra then
      local fp, fa = freqs_em(d, l)
      local freq_digitada = (palavra ~= M.sem_acento(palavra)) and fa or fp
      if freq_digitada and freq_digitada > 0
          and config.min_freq_nao_corrige > 0
          and freq_digitada >= config.min_freq_nao_corrige then
        return nil -- forma real e comum: preserva ("esta", "têm", "quê"...)
      end
      return canon
    end
    return nil -- já está com o acento certo
  end

  local perm = M.erro_permitido(#chave)
  local best, bdist, bfreq = nil, perm + 1, -1
  -- Prefixo relaxado até len-3: pega erro no meio da palavra ("palvra" ->
  -- "palavra"); abaixo disso o risco de correção errada sobe de mais.
  for k = #chave, math.max(1, #chave - 3), -1 do
    local lo, hi = M.intervalo_por_prefixo(d, 1, d.n, chave:sub(1, k))
    if lo <= hi then
      for i = lo, hi do
        local c = chave_em(d, i)
        if math.abs(#c - #chave) <= perm then -- gate barato antes do DL
          local dist = M.damerau_levenshtein(chave, c)
          if dist <= perm then
            -- Probabilidade (unigrama): frequência da grafia dominante.
            -- Menor distância vence; empate vai para a mais frequente —
            -- assim "paa" vira "para" (freq 1,9M) e não "pá" (freq 11k).
            local fp, fa = freqs_em(d, i)
            local freq = math.max(fp, fa)
            if dist < bdist or (dist == bdist and freq > bfreq) then
              best, bdist, bfreq = i, dist, freq
            end
          end
        end
      end
    end
  end
  if best then return canon_em(d, best) end
  return nil
end

-- ===== Acompanhar o texto digitado =====
-- IMPORTANTE: o app reporta posições em unidades UTF-16 (Java) no
-- vim.get_sel/vim.replace, mas o vim.get_text() entrega bytes UTF-8. Com
-- acentos (é = 2 bytes / 1 unidade) os índices divergem — então a passada
-- converte byte<->unidade com a tabela abaixo. Assume base == 0 (campo de
-- texto normal); em docs gigantes onde o editor desloca startOffset, não edita.

--- Tabela {unidade -> byte de início (1-based)} + contagem de unidades UTF-16.
function M.tabela_char_byte(texto)
  local tb, u, n = {}, 0, #texto
  local i = 1
  while i <= n do
    local b = texto:byte(i)
    if b >= 0xF0 and b < 0xF8 then -- astral (4 bytes) = 2 unidades (raro aqui)
      u = u + 1; tb[u] = i
      u = u + 1; tb[u] = i
      i = i + 4
    elseif b >= 0xC2 then          -- 2 ou 3 bytes, 1 unidade
      u = u + 1; tb[u] = i
      i = i + (b < 0xE0 and 2 or 3)
    else                           -- 1 byte ASCII
      u = u + 1; tb[u] = i
      i = i + 1
    end
  end
  tb[u + 1] = n + 1
  return tb, u
end

--- Nº de unidades UTF-16 de um texto (get_sel vem nessa unidade).
function M.unidades_utf16(texto)
  local _, u = M.tabela_char_byte(texto)
  return u
end

--- Última palavra antes do cursor (caret, em bytes como o vim.get_sel).
--  Devolve (wstart1, wend1 1-based, palavra, comitada). "Comitada" = o que
--  está logo antes do cursor é um separador (espaço/pontuação) -> chegou a
--  hora de corrigir. Caso contrário a palavra ainda está sendo digitada.
function M.ultima_palavra(texto, caret)
  if type(texto) ~= "string" or not caret or caret <= 0 then
    return nil, nil, "", false
  end
  -- Caractere (completo) imediatamente antes do cursor.
  local cstart = inicio_char(texto, caret)
  local antes = texto:sub(cstart, caret)
  local comitada = not M.eh_letra(antes)
  if comitada then
    local p = cstart - 1
    while p >= 1 do
      local s = inicio_char(texto, p)
      if M.eh_letra(texto:sub(s, p)) then p = s - 1 else break end
    end
    local wstart1 = p + 1
    local wend1 = cstart - 1
    return wstart1, wend1, texto:sub(wstart1, wend1), true
  end
  local p = cstart
  while p >= 1 do
    local s = inicio_char(texto, p)
    if M.eh_letra(texto:sub(s, p)) then p = s - 1 else break end
  end
  local wstart1 = p + 1
  local palavra = texto:sub(wstart1, caret)
  if palavra == "" then return nil, nil, "", false end
  return wstart1, caret, palavra, false
end

local function assegura_dados()
  if dados then return true end
  -- Índice embutido nos plugins (dicionario_dados.lua): sem download, offline.
  local d, err = M.carregar_embutido()
  if not d then
    d, err = M.carregar(config.dados_dir)
  end
  if d then
    dados = d
    return true
  end
  if tostring(err) ~= erro_carregou then
    erro_carregou = tostring(err)
    if vim then vim.status(":dict — sem índice (" .. erro_carregou .. ")") end
  end
  return false
end

--- Passada do watcher: roda no vim.interval. Na prática: acha a palavra atual,
--  corrige se comitada, ou estreita a faixa binária pelo prefixo digitado.
function M.passada()
  if not config.ativado or not (vim and vim.get_text) then return end
  if not assegura_dados() then return end

  local texto = vim.get_text()
  if type(texto) ~= "string" or texto == "" then return end
  local s, e = vim.get_sel()
  if not (s and e and s == e) then return end -- seleção: não mexe aqui

  -- caret em unidades UTF-16 (como o get_sel); converto p/ byte p/ varrer o texto.
  local tb, unidades = M.tabela_char_byte(texto)
  if s < 0 or s > unidades then return end -- base do editor ≠ 0: campo gigante
  local caretB = tb[s + 1] - 1 -- último byte (1-based) antes do cursor
  if caretB <= 0 then return end

  local wstart1, wend1, palavra, comitada = M.ultima_palavra(texto, caretB)
  if comitada then
    intervalo.prefixo, intervalo.lo, intervalo.hi = "", 1, 0
    if wend1 > wstart1 and palavra then
      local corr = M.corrigir_palavra(dados, palavra)
      if corr then
        -- inicia da palavra (0-based em unidades UTF-16) até INCLUDINDO o
        -- separador ao lado do caret: a correção entrega palavra+separador,
        -- então o espaço (ou o enter) nunca some.
        local cs
        for i = s, 1, -1 do
          if tb[i] == wstart1 then cs = i; break end
        end
        if cs then
          local p0, p1 = cs - 1, s
          local sep = texto:sub(tb[s], tb[s + 1] - 1) -- espaço/enter antes do caret
          local novo = corr .. sep
          if not (fix and fix.p0 == p0 and fix.p1 == p1 and fix.texto == novo) then
            fix = { p0 = p0, p1 = p1, texto = novo }
            vim.replace(p0, p1, novo)
            if config.aviso then
              vim.status("dicionário: " .. palavra .. " → " .. corr)
            end
          end
        end
      end
    end
    return
  end

  -- Palavra em construção: estreita a faixa binária pelo que já foi escrito.
  if wstart1 and palavra and #palavra >= 1 then
    local chave = M.sem_acento(palavra)
    local cresceu = intervalo.prefixo ~= ""
      and #chave > #intervalo.prefixo
      and chave:sub(1, #intervalo.prefixo) == intervalo.prefixo
    if cresceu and intervalo.hi >= intervalo.lo then
      local l, h = M.intervalo_por_prefixo(dados, intervalo.lo, intervalo.hi, chave)
      if l <= h then
        intervalo.lo, intervalo.hi = l, h
      else
        intervalo.lo, intervalo.hi = M.intervalo_por_prefixo(dados, 1, dados.n, chave)
      end
    else
      intervalo.lo, intervalo.hi = M.intervalo_por_prefixo(dados, 1, dados.n, chave)
    end
    intervalo.prefixo = chave
    if config.mostrar_candidatos then
      local n = intervalo.hi - intervalo.lo + 1
      if n > 0 then
        vim.status(chave .. " → " .. n .. " candidato(s)")
      else
        vim.status(chave .. " → (nenhum)")
      end
    end
  else
    intervalo.prefixo, intervalo.lo, intervalo.hi = "", 1, 0
  end
end

-- ===== Ciclo de vida =====
function M.iniciar()
  if not (vim and vim.interval) then return end
  if handle then vim.clear_interval(handle) end
  handle = vim.interval(config.intervalo_ms, M.passada)
end

function M.parar()
  if handle and vim and vim.clear_interval then
    vim.clear_interval(handle)
  end
  handle = nil
end

-- ===== :dict =====
function M.comando(args)
  args = args or {}
  local a = args[1]
  if a == "on" then
    M.setup(config and { ativado = true } or nil)
    vim.status(":dict — correção ligada")
  elseif a == "off" then
    M.setup({ ativado = false })
    vim.status(":dict — correção desligada")
  elseif a == "status" then
    local n = dados and dados.n or 0
    vim.status((":dict — %s | %d palavras | %s | len>=%d")
      :format(config.ativado and "ligado" or "desligado", n,
        config.dados_dir, config.min_len))
  elseif a and #args >= 1 then
    -- :dict <palavra>: mostra a correção que seria aplicada (não edita).
    local palavra = tostring(a)
    if not assegura_dados() then return end
    local corr = M.corrigir_palavra(dados, palavra)
    if corr then
      vim.status("dicionário: " .. palavra .. " → " .. corr)
    else
      vim.status("dicionário: '" .. palavra .. "' nada a corrigir")
    end
  else
    vim.status(":dict — " .. (config.ativado and "ligado" or "desligado")
      .. " (on/off, status, ou <palavra> para testar)")
  end
end

-- ===== Auto-início (padrão dos plugins) =====
M.setup()
M.iniciar()
if vim then
  vim.register("dict", function(...) M.comando({ ... }) end)
end

return M