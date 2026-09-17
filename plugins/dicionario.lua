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
min_freq_nao_corrige = 30000, -- forma PLANTA digitada com freq >= isso é
                                -- "palavra em uso" e não deve ser trocada
  ratio_plana_real = 0.10,     -- planta concorre de verdade com o acentuado se
                                -- a freq dela >= 10% da dele (vira/virá, e não
                                -- "voce" contra "você") -> preserva
  modelo_ativado = true,      -- mini-modelo de contexto (bigramas/trigramas)
  peso_contexto = 1.0,        -- peso do contexto no desempate do fuzzy
  janela_ctx = 5,             -- janela longa de contexto: quantas palavras
                                -- anteriores (além de antes/antes2) contam na
                                -- decisão. 0 = só o trigrama/bigrama atual.
  decaimento_janela = 0.85,   -- a palavra da posição k da janela pesa
                                -- decaimento^(k-1) no desempate
  peso_janela_ctx = 1.0,      -- peso da janela longa frente ao contexto lokal
  grafo_ativado = true,       -- grafo de palavras correlacionadas (arestas =
                                -- coocorrência palavra→palavra) vota no desempate
  peso_grafo = 1.0,           -- peso do voto do grafo frente ao contexto/local
  prefixo_freq_min = 5000,    -- só "completa" prefixo se a palavra for comum
  depurar = false,            -- :dict debug liga; mostra o que a passada vê
  modo_modelo = false,        -- :dict modo liga: desliga as regras determinísticas
                                -- (planas_legitimas, min_freq_nao_corrige,
                                -- ratio_plana_real) e corrige "pela moda/modelo";
                                -- o vocabulário (dicionario_dados) continua sendo
                                -- a base obrigatória de palavras e acentos.
  mostrar_candidatos = false,-- durante a digitação, mostra o nº de candidatos
  dados_dir = "/sdcard/keyboard-lua/data/dicionario",
}
local config = {}
-- Estado do plugin (declarado no topo p/ os closures abaixo capturarem o local).
local dados = nil       -- índice carregado (lazy)
local erro_carregou = "" -- status mostrado uma vez se o arquivo faltar
local handle = nil      -- handle do vim.interval
local intervalo = { prefixo = "", lo = 1, hi = 0 } -- faixa corrente (halving)
local fix = nil         -- último (p0, p1, texto) corrigido, p/ não repetir
-- Últimas duas palavras comitadas pelo usuário (contexto p/ corrigir melhor:
-- "ele fabrica" ≠ "a fabrica"). atualizadas a cada passada.
local ultimas = { antes = "", antes2 = "" }

-- Planas herdadas: a grafia SEM acento também é palavra real, então nunca se
-- "conserta" às cegas. "cn" = o acento só entra com sinal forte de
-- substantivo/adjetivo (determinante antes: "a fabrica" -> "a fábrica");
-- "nu" = nunca se acrescenta o acento (a plana já é a forma certa: "facas",
-- "avos", "secretaria").
local PLANAS_LEGITIMAS = {
  analise = "cn", critica = "cn", criticas = "cn", copia = "cn",
  distancia = "cn", duvida = "cn", duvidas = "cn", estagio = "cn",
  estudio = "cn", exercito = "cn", fabrica = "cn", fabricas = "cn",
  influencia = "cn", medica = "cn", medico = "cn", numero = "cn",
  pratica = "cn", praticas = "cn", publica = "cn", publicas = "cn",
  publico = "cn",
  avos = "nu", facas = "nu", secretaria = "nu", secretarias = "nu",
}

-- Determinantes: palavra antes sinaliza substantivo/adjetivo na frente (dá
-- aval para acrescentar o acento na canônica: "a fabrica" -> "a fábrica").
local DETERMINANTE = {
  a = true, as = true, o = true, os = true,
  um = true, uma = true, uns = true, umas = true,
  esta = true, este = true, estas = true, estes = true,
  essa = true, esse = true, essas = true, esses = true,
  aquela = true, aquele = true, aquelas = true, aqueles = true,
  minha = true, minhas = true, meu = true, meus = true,
  sua = true, suas = true, seu = true, seus = true,
  nossa = true, nossas = true, nosso = true, nossos = true,
  vossa = true, vossas = true, vosso = true, vossos = true,
  da = true, ["do"] = true, das = true, dos = true,
  na = true, no = true, nas = true,
  ["à"] = true, ["às"] = true,
}

-- "Delegação" QWERTY (base do layout atual): vizinhança por tecla. Usada para
-- ponderar substituições no custo de edição do mini-modelo (erro de dedo).
local VIZ = {
  q = "was", w = "qeasd", e = "wrsdf", r = "etdfg", t = "ryfgh",
  y = "tughj", u = "yihjk", i = "uojkl", o = "ipkl", p = "ol",
  a = "qwszx", s = "awedzxc", d = "aserfcxv", f = "asdrtgvcb",
  g = "sdfrtyhbvn", h = "dfgytujnbm", j = "fghuikmn",
  k = "ghjiolm", l = "hjkop", z = "asdx", x = "asdzc",
  c = "sdfxzv", v = "dfgxcb", b = "fghcvm", n = "ghjbmv", m = "hjkun",
}

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
  cfg.peso_contexto = math.max(0, tonumber(cfg.peso_contexto) or defaults.peso_contexto)
  cfg.janela_ctx = math.max(0, math.floor(tonumber(cfg.janela_ctx) or defaults.janela_ctx))
  cfg.decaimento_janela = math.max(0, math.min(1, tonumber(cfg.decaimento_janela) or defaults.decaimento_janela))
  cfg.peso_janela_ctx = math.max(0, tonumber(cfg.peso_janela_ctx) or defaults.peso_janela_ctx)
  cfg.grafo_ativado = cfg.grafo_ativado ~= false
  cfg.peso_grafo = math.max(0, tonumber(cfg.peso_grafo) or defaults.peso_grafo)
  cfg.dados_dir = tostring(cfg.dados_dir or defaults.dados_dir)
  cfg.min_freq_nao_corrige = math.max(0, math.floor(tonumber(cfg.min_freq_nao_corrige) or 30000))
  cfg.ratio_plana_real = math.max(0, tonumber(cfg.ratio_plana_real) or 0.10)
  local pl = {}
  for w, k in pairs(PLANAS_LEGITIMAS) do pl[w] = k end
  if type(cfg.planas_legitimas) == "table" then
    for w, k in pairs(cfg.planas_legitimas) do pl[w] = k end
  end
  cfg.planas_legitimas = pl
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

--- A palavra tem acento? (à á â ã ç é ê í ó ô õ ü... todos caem em UTF-8 0xC3 0x8x-Bx)
-- Nota: não usar sem_acento aqui — ela minúscula tudo e letra maiúscula plana
-- (ex.: "Voce") não é acento.
function M.tem_acento(s)
  return s:find("[\195][\128-\191]") ~= nil
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

-- ===== Mini-modelo de contexto (n-gramas) =================================
-- plugins/dicionario_modelo.lua (GERADO): incorporado igual ao índice.
-- Formato de cada linha (tem tab no meio; ctx dos trigramas tem espaço):
--   B<ctx>\t<total>\t<alvo:cont>\t<alvo:cont>...
--   T<ctx p2 p1>\t<total>\t...

--- Constrói o modelo a partir do texto bruto do módulo embutido. Resultado:
--  { B = {ctx -> {alvo=cont}}, somaB = {ctx -> total}, T = {...}, somaT,
--    genero = {palavra -> "F"|"M"}, inverso = {alvo -> {ctx=p}} }
--  O inverso é o grafo palavra→palavra invertido (para cada alvo, quais
--  contextos o precedem com que probabilidade). O genero é derivado das
--  contagens P(palavra|a/uma) vs P(palavra|o/um).
function M._construir_modelo(texto)
  local B, T, somaB, somaT = {}, {}, {}, {}
  for l in texto:gmatch("[^\n]+") do
    local pre, ctx, tot, resto = l:match("^([BT])([^\t]+)\t(%d+)(.*)$")
    if pre and ctx then
      local t = {}
      for alvo, cnt in resto:gmatch("\t([%a]+):(%d+)") do
        t[alvo:lower()] = tonumber(cnt)
      end
      if pre == "B" then B[ctx] = t; somaB[ctx] = tonumber(tot)
      else T[ctx] = t; somaT[ctx] = tonumber(tot) end
    end
  end
  -- Grafo inverso: para cada alvo, quais contextos o precedem (P(alvo|ctx)).
  local inverso = {}
  for ctx, tgt in pairs(B) do
    local tot = somaB[ctx]
    if tot and tot > 0 then
      for alvo, cnt in pairs(tgt) do
        local inv = inverso[alvo]
        if not inv then inv = {}; inverso[alvo] = inv end
        inv[ctx] = cnt / tot
      end
    end
  end
  -- Gênero derivado estatisticamente: P(palavra|"a"/"uma") vs P(palavra|"o"/"um").
  local genero = {}
  for _, artigo_fem in ipairs({"a", "uma"}) do
    local tgt = B[artigo_fem]
    if tgt then
      for alvo, cnt in pairs(tgt) do
        local g = genero[alvo]
        if not g then g = {f = 0, m = 0}; genero[alvo] = g end
        g.f = g.f + cnt
      end
    end
  end
  for _, artigo_masc in ipairs({"o", "um"}) do
    local tgt = B[artigo_masc]
    if tgt then
      for alvo, cnt in pairs(tgt) do
        local g = genero[alvo]
        if not g then g = {f = 0, m = 0}; genero[alvo] = g end
        g.m = g.m + cnt
      end
    end
  end
  local gen_final = {}
  for pal, g in pairs(genero) do
    if g.f + g.m >= 3 then
      gen_final[pal] = (g.f > g.m * 1.5) and "F" or ((g.m > g.f * 1.5) and "M" or nil)
    end
  end
  return { B = B, T = T, somaB = somaB, somaT = somaT,
           inverso = inverso, genero = gen_final }
end

function M.carregar_modelo_embutido()
  local ok, res = pcall(function() return require("dicionario_modelo") end)
  if not ok then return nil end
  if type(res) ~= "string" or res:sub(1, 1) ~= "B" then return nil end
  return M._construir_modelo(res)
end

function M.carregar_modelo(dados_dir)
  local texto = io.open(dados_dir .. "/dicionario_modelo.dat", "r")
  if not texto then return nil end
  local t = texto:read("*a")
  texto:close()
  return M._construir_modelo(t)
end

--- Probabilidade de [alvo] dado o contexto [antes2 antes] (trigrama, depois
--  bigrama; backoff). nil quando o alvo não ocorre nesse contexto.
function M.p_ctx(modelo, antes2, antes, alvo)
  if not modelo or not alvo then return nil end
  if antes2 and antes2 ~= "" and antes and antes ~= "" then
    local tt = modelo.T
    if tt then
      local k = antes2 .. " " .. antes
      local c = tt[k]
      if c and c[alvo] then return c[alvo] / modelo.somaT[k] end
    end
  end
  if antes and antes ~= "" then
    local bb = modelo.B
    if bb then
      local c = bb[antes]
      if c and c[alvo] then return c[alvo] / modelo.somaB[antes] end
    end
  end
  return nil
end

--- Fila de contexto: as últimas `n` palavras do texto ANTES do caret,
--  da mais recente para a mais antiga (fila[1] = imediata antes). Usa o
--  mesmo caminhar do `antes/antes2` atuais, só que repetido até `n`. Palavras
--  com acento são normalizadas (sem_acento) porque as B/T são sem acento.
function M.ultimas_palavras_no_texto(texto, caretB, n)
  local fila = {}
  if not texto or type(texto) ~= "string" or texto == "" then return fila end
  n = math.max(1, math.floor(n or 5))
  local pos = caretB
  for _ = 1, n do
    local ini, palavra = M.palavra_anterior_inicio(texto, pos)
    if not ini then break end
    local p = M.sem_acento(palavra)
    if p and p ~= "" then
      fila[#fila + 1] = p
      pos = ini - 1
    else
      break
    end
  end
  return fila
end

--- Contexto de janela longa: soma de log-probs ponderadas por distância.
--  Cada palavra da fila vota como antecedente — a da posição 1 (imediata)
--  com trigrama→bigrama (backoff atual), as demais com bigrama; o voto da
--  posição k pesa decaimento_janela^(k-1). Peso total = peso_janela_ctx.
--  Retorna o Σ log(p)*peso (pode ser negativo), ou nil se ninguém votou.
--  Lado do usuário: várias B/T já existem no modelo embutido — nenhuma
--  regeneração; a janela só junta os votos com decaimento.
function M.p_ctx_janela(modelo, fila, alvo)
  if not modelo or not fila or type(fila) ~= "table" or #fila == 0 then return nil end
  if not alvo then return nil end
  local dec = config.decaimento_janela
  local peso_total = config.peso_janela_ctx
  local soma = 0
  local soma_pesos = 0
  local votaram = 0
  for k, w in ipairs(fila) do
    if w and w ~= "" then
      local p
      if k == 1 then
        -- voto mais próximo: trigrama → bigrama (backoff de sempre)
        p = M.p_ctx(modelo, fila[2], w, alvo)
      else
        -- distantes: só o bigrama (sem trigrama espalhado pela janela)
        p = M.p_ctx(modelo, nil, w, alvo)
      end
      if p and p > 0 then
        local peso = dec ^ (k - 1)
        soma = soma + peso * math.log(p)
        soma_pesos = soma_pesos + peso
        votaram = votaram + 1
      end
    end
  end
  if votaram == 0 then return nil end
  -- prob geométrica (exp da média de logs) → mesma escala 0..1 de p_ctx.
  return math.exp(peso_total * soma / soma_pesos)
end

--- Palavras de função (só pontes entre palavras de conteúdo). Não entram no
--  grafo como ORIGEM de aresta: "cortar com uma faa" vota por "cortar" (conteúdo),
--  não por "com"/"uma". Chaves normalizadas (sem acento), como o modelo.
local PALAVRAS_LIGACAO = {}
for _w in ("a as o os e ou nem mas pois de do da dos das para pra pro per em no na nos nas nao sem com que se um uma uns umas por ao aos pelo pela pelos pelas ate ja so tambem ainda quando onde como aquela aquele aquelas aqueles este esta estes estas esse essa esses essas isto isso se si tu voce voces eu nos vcs me te lhe lhes ele ela eles elas si"):gmatch("%S+") do
  PALAVRAS_LIGACAO[_w] = true
end

--- Artigos que definem gênero esperado para a próxima palavra.
local ARTIGOS_FEM = { a = true, uma = true }
local ARTIGOS_MASC = { o = true, um = true }

--- Voto do GRAFO de palavras correlacionadas: usa o grafo inverso do modelo
--  (P(alvo|ctx) derivado dos bigramas embutidos) + bônus de gênero quando
--  o artigo imediato define o gênero esperado.  Tudo derivado dos dados —
--  nenhuma aresta manual/seed.  Retorna nil quando nada vota.
function M.voto_grafo(modelo, fila, alvo)
  if not config.grafo_ativado or not modelo or not alvo then return nil end
  if not fila or type(fila) ~= "table" or #fila == 0 then return nil end
  local gen = modelo.genero and modelo.genero[alvo] or nil
  local dec = config.decaimento_janela
  local soma, soma_pesos, votaram = 0, 0, 0
  for k, w in ipairs(fila) do
    if w and w ~= "" and not PALAVRAS_LIGACAO[w] then
      -- Estatística do modelo: P(alvo | w) via bigrama (p_ctx existente)
      local p
      if k == 1 then
        p = M.p_ctx(modelo, fila[2], w, alvo)
      else
        p = M.p_ctx(modelo, nil, w, alvo)
      end
      local v = (p and p > 0) and math.log(p) or 0
      if v ~= 0 then
        local peso = dec ^ (k - 1)
        soma = soma + peso * v
        soma_pesos = soma_pesos + peso
        votaram = votaram + 1
      end
    end
  end
  -- Bônus de gênero: se o artigo imediato (fila[1]) define gênero e o
  -- alvo tem gênero derivado do modelo, dá bônus/penalidade.
  if gen and #fila >= 1 then
    local art = fila[1]
    local bonus = 0
    if ARTIGOS_FEM[art] and gen == "F" then
      bonus = math.log(2)
    elseif ARTIGOS_MASC[art] and gen == "M" then
      bonus = math.log(2)
    elseif ARTIGOS_FEM[art] and gen == "M" then
      bonus = -math.log(2)
    elseif ARTIGOS_MASC[art] and gen == "F" then
      bonus = -math.log(2)
    end
    if bonus ~= 0 then
      soma = soma + bonus
      soma_pesos = soma_pesos + 1
      votaram = votaram + 1
    end
  end
  if votaram == 0 then return nil end
  return math.exp(config.peso_grafo * soma / soma_pesos)
end

--- Custo de "digitar s quando se queria t", ponderado por vizinhança QWERTY
--  (erro de dedo): substituição vizinha 0.6, longe 1.2, transposição 0.7,
--  inserção/deleção 1.0. Levenshtein com 3 linhas (guarda a diagonal anterior
--  para a transposição).
function M.custo_edicao(s, t)
  local n, m = #s, #t
  if n == 0 then return m end
  if m == 0 then return n end
  local d2, d1, d0 = {}, {}, {}
  for j = 0, m do d2[j], d1[j] = 0, j end
  local function peso_sub(i, j)
    local a, b = s:byte(i), t:byte(j)
    if a == b then return 0 end
    local v = VIZ[string.char(a)]
    if v and v:find(string.char(b), 1, true) then return 0.6 end
    return 1.2
  end
  for i = 1, n do
    local sb, sprev = s:byte(i), s:byte(i - 1)
    d0[0] = i
    for j = 1, m do
      local c = math.min(d1[j] + 1, d0[j - 1] + 1, d1[j - 1] + peso_sub(i, j))
      if i > 1 and j > 1 and sb == t:byte(j - 1) and sprev == t:byte(j) then
        c = math.min(c, d2[j - 2] + 0.7)
      end
      d0[j] = c
    end
    d2, d1, d0 = d1, d0, d2
  end
  return d1[m]
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
--  [antes] é a palavra que vinha imediatamente antes (contexto): usada só nas
--  homógrafas herdadas ("ele fabrica" \~ "a fabrica").
--  1. casa exata da chave sem acento -> devolve a canônica com acento
--     ("voce" -> "você"); grafias reais são preservadas:
--     * acento digitado numa palavra que existe no índice (nunca rebaixa:
--       "pôr", "pôde", "vêm", "dê");
--     * forma plana comum em si ou concorrente real da acentuada
--       ("esta", "tem", "e", "nos"; "vira" frente a "virá");
--     * planas herdadas (planas_legitimas): "nu" nunca muda; "cn" entra o
--       acento só sob determinante antes ("a fabrica" -> "a fábrica", mas
--       "ele fabrica" fica).
--  2. senão, fuzzy: Damerau-Levenshtein <= erros permitidos dentro da faixa
--     do prefixo digitado (relaxando o prefixo em até 3 letras). Empate de
--     distância escolhe a palavra mais frequente (probabilidade unigrama).
--  3. maiúsculas são puladas (nomes próprios), por padrão
function M.corrigir_palavra(d, palavra, antes, antes2, fila)
  if not d or type(palavra) ~= "string" then return nil end
  if #palavra < config.min_len then return nil end
  if config.pular_maiuscula and palavra:match("^%u") then return nil end

  local chave = M.sem_acento(palavra)
  local l, h = M.intervalo_por_prefixo(d, 1, d.n, chave)
  if l <= h and chave_em(d, l) == chave then
    local canon = canon_em(d, l)
    if canon ~= palavra then
      if M.tem_acento(palavra) then
        -- Digitou um acento numa grafia que EXISTE no índice: é forma real
        -- (verbo "pôr", "pôde", "vêm", "dê"...). Nunca remover/rebaixar o
        -- acento que o usuário digitou de propósito.
        return nil
      end
      -- Modo só-modelo: nenhuma regra determinística trava — corrige para a
      -- canônica (a grafia que a moda/modelo manda), como em "esta" -> "está",
      -- "tem" -> "têm", "porem" -> "porém", "a fabrica" -> "a fábrica".
      if config.modo_modelo then return canon end
      -- Planas herdadas (homógrafas): decide pelo contexto, não pela moda.
      local kind = config.planas_legitimas[palavra]
      if kind then
        if kind == "cn" then
          local a = antes and M.sem_acento(antes) or ""
          if DETERMINANTE[a] then return canon end -- "a fabrica" -> "a fábrica"
        end
        return nil -- "ele fabrica", "as facas", "dois avos" ficam como estão
      end
      -- Forma plana: preserva quando é palavra real e viva — ou por ser comum
      -- em si ("esta", "tem", "e", "nos") ou por concorrer de verdade com a
      -- acentuada ("vira"/"virá", 70% da freq — não é erro).
      local fp, fa = freqs_em(d, l)
      if fp and fp > 0 and (
          (config.min_freq_nao_corrige > 0
            and fp >= config.min_freq_nao_corrige)
          or (config.ratio_plana_real > 0
            and fa and fa > 0
            and fp >= fa * config.ratio_plana_real)) then
        return nil
      end
      return canon
    end
    -- Grafia digitada == chave == canônica: é palavra real. mas se for uma
    -- grafia de frequência baixíssima (lixeira/erro do corpus) e o grafo
    -- de contexto (modelo embutido) tiver P(candidato|contexto) forte para
    -- um candidato próximo, reconduz — senão, preserva (nil).
    if config.grafo_ativado and d.modelo and fila and #fila > 0 then
      local fp0, fa0 = freqs_em(d, l)
      if math.max(fp0, fa0) < config.min_freq_nao_corrige then
        local perm0 = M.erro_permitido(#chave)
        local melhor_i, melhor_d, melhor_e = nil, perm0 + 1, -1 / 0
        for k0 = #chave, math.max(1, #chave - 3), -1 do
          local lo0, hi0 = M.intervalo_por_prefixo(d, 1, d.n, chave:sub(1, k0))
          if lo0 <= hi0 then
            for i0 = lo0, hi0 do
              local c0 = chave_em(d, i0)
              if math.abs(#c0 - #chave) <= perm0 then
                local d0 = M.damerau_levenshtein(chave, c0)
                if d0 <= perm0 then
                  local v0 = M.voto_grafo(d.modelo, fila, c0)
                  if v0 and (d0 < melhor_d or (d0 == melhor_d and v0 > melhor_e)) then
                    melhor_i, melhor_d, melhor_e = i0, d0, v0
                  end
                end
              end
            end
          end
        end
        if melhor_i and melhor_e > 0 then
          -- Devolve a grafia CERTA para o contexto: o canon (acentuado) quando
          -- a grafia digitada não é viva ("faa"->"faca"? não), ou a própria
          -- grafia viva quando ela concorre com o acentuado (razão do par
          -- "faca" vs "faça": aqui "faca" é o instrumento, não o verbo).
          local mc = chave_em(d, melhor_i)
          local mf, ma = freqs_em(d, melhor_i)
          if ma and ma > 0 and config.ratio_plana_real > 0
             and mf and mf >= ma * config.ratio_plana_real then
            return mc
          end
          return canon_em(d, melhor_i)
        end
      end
    end
    return nil -- já está com o acento certo
  end

  -- Completar prefixo com confiança EXTRA-ALTA (só quando o digitado é o
  -- começo exato de uma ÚNICA palavra comum com exatamente 1 letra a mais:
  -- "caf" -> "café", nunca "cá"). Sem contexto suficiente a grafia plena
  -- (ex.: "com", "con") tem chave própria e já saiu no caminho exato acima.
  if config.modelo_ativado and #chave >= config.min_len then
    local pref_best, pref_freq, pref_n = nil, -1, 0
    -- Só o prefixo COMPLETO: um "completar" exige o digitado como começo exato
    -- (len+1), então a varredura de k menor só contaria a mesma palavra 2×.
    local lo, hi = M.intervalo_por_prefixo(d, 1, d.n, chave)
    if lo <= hi then
      for i = lo, hi do
        local c = chave_em(d, i)
        if #c == #chave + 1 and c:sub(1, #chave) == chave then
          local fp, fa = freqs_em(d, i)
          local freq = math.max(fp, fa)
          if freq >= config.prefixo_freq_min then
            pref_n = pref_n + 1
            if freq > pref_freq then pref_best, pref_freq = i, freq end
          end
        end
      end
    end
    if pref_n == 1 and pref_best then return canon_em(d, pref_best) end
  end

  local perm = M.erro_permitido(#chave)
  local best, bdist, bescore = nil, perm + 1, -1 / 0
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
            -- Escore unigrama (frequência da grafia dominante) + desempate
            -- por contexto (n-gramas): "ela falo" tende a "fala"; sem modelo
            -- vira só a moda (equivale ao comportamento antigo). Menor
            -- distância vence; empate vai para o maior escore — "paa" ->
            -- "para" (freq 1,9M) e não "pá" (freq 11k).
            local fp, fa = freqs_em(d, i)
            local freq = math.max(fp, fa)
            local escore = math.log(freq + 1)
            if config.modelo_ativado and d.modelo then
              local a1 = antes and M.sem_acento(antes) or ""
              local a2 = antes2 and M.sem_acento(antes2) or ""
              if fila and #fila > 0 then
                p = M.p_ctx_janela(d.modelo, fila, chave_em(d, i))
              else
                p = M.p_ctx(d.modelo, a2, a1, chave_em(d, i))
              end
              if p and p > 0 then
                escore = escore + config.peso_contexto * math.log(p)
              end
              -- Voto do grafo de palavras correlacionadas (arestas de
              -- coocorrência palavra→palavra, palavras de função fora):
              -- quando a janela n-grama não vota, o grafo ainda desata o
              -- empate sobre a grafia dominante.
              local g = M.voto_grafo(d.modelo, fila, chave_em(d, i))
              if g and g > 0 then escore = escore + math.log(g) end
            end
            if dist < bdist or (dist == bdist and escore > bescore) then
              best, bdist, bescore = i, dist, escore
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

--- Palavra inteira (só letras) que termina imediatamente antes do byte [fim-1]
--  de uma palavra. Devolve nil se não houver (início do texto).
function M.palavra_anterior(texto, fim_atual)
  local p = fim_atual - 1
  while p >= 1 do
    local s = inicio_char(texto, p)
    if M.eh_letra(texto:sub(s, p)) then break end
    p = s - 1
  end
  if p < 1 then return nil end
  local f = p
  while p >= 1 do
    local s = inicio_char(texto, p)
    if M.eh_letra(texto:sub(s, p)) then p = s - 1 else break end
  end
  if p + 1 > f then return nil end
  return texto:sub(p + 1, f)
end

--- Como palavra_anterior, mas também devolve o byte inicial (p/ encadear
--  "duas anteriores" ao montar o contexto do trigrama).
function M.palavra_anterior_inicio(texto, fim_atual)
  local p = fim_atual - 1
  while p >= 1 do
    local s = inicio_char(texto, p)
    if M.eh_letra(texto:sub(s, p)) then break end
    p = s - 1
  end
  if p < 1 then return nil end
  local f = p
  while p >= 1 do
    local s = inicio_char(texto, p)
    if M.eh_letra(texto:sub(s, p)) then p = s - 1 else break end
  end
  if p + 1 > f then return nil end
  return p + 1, texto:sub(p + 1, f)
end

function M.ultimas_palavras()
  return { antes2 = ultimas.antes2, antes = ultimas.antes }
end

local function assegura_dados()
  if dados then return true end
  -- Índice embutido nos plugins (dicionario_dados.lua): sem download, offline.
  local d, err = M.carregar_embutido()
  if not d then
    d, err = M.carregar(config.dados_dir)
  end
  if d then
    if config.modelo_ativado then
      -- Mini-modelo de contexto: embutido, com fallback no diretório de dados.
      d.modelo = M.carregar_modelo_embutido()
      if not d.modelo then
        d.modelo = M.carregar_modelo(config.dados_dir)
      end
    end
    dados = d
    if vim then vim.status(":dict — " .. d.n .. " chaves"
      .. (d.modelo and " (+modelo)" or " (modelo falhou)")) end
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
    if config.depurar then
      local sup = "s=" .. tostring(s) .. " caretB=" .. tostring(caretB)
        .. " wstart=" .. tostring(wstart1) .. " com=" .. tostring(comitada)
        .. " texto<" .. texto .. ">"
      vim.status(":dict debug: " .. sup)
    end
    if wend1 > wstart1 and palavra then
      local a1, antes = M.palavra_anterior_inicio(texto, wstart1)
      local antes2 = ""
      if a1 then
        local _, b2 = M.palavra_anterior_inicio(texto, a1)
        antes2 = b2 or ""
      end
      ultimas.antes2, ultimas.antes = ultimas.antes, antes or ""
      local corr = M.corrigir_palavra(dados, palavra, antes, antes2)
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
  elseif a == "debug" then
    config.depurar = not config.depurar
    local info = "desligado"
    if config.depurar then
      info = "ligado — digite uma palavra e dê espaço; veja o status da passada"
    end
    vim.status(":dict debug " .. info)
  elseif a == "modo" then
    config.modo_modelo = not config.modo_modelo
    vim.status(":dict " .. (config.modo_modelo
      and "só-modelo (regras desligadas)" or "conservador (regras ligadas)"))
  elseif a == "status" then
    local n = dados and dados.n or 0
    local m = dados and dados.modelo and "modelo ok"
        or (config.modelo_ativado and "sem modelo" or "modelo off")
    vim.status((":dict — %s | %d palavras | %s | len>=%d | %s | %s")
      :format(config.ativado and "ligado" or "desligado", n,
        config.dados_dir, config.min_len, m,
        config.modo_modelo and "só-modelo" or "regras"))
  elseif a and #args >= 1 then
    -- :dict <palavra>: mostra a correção que seria aplicada (não edita).
    local palavra = tostring(a)
    if not assegura_dados() then return end
    local corr = M.corrigir_palavra(dados, palavra, ultimas.antes or nil, ultimas.antes2)
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