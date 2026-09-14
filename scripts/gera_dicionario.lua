-- gera_dicionario.lua — transforma uma lista de palavras (PT) no formato
-- "chave\TABcanonical\TABfreq_texto\TABfreq_acentuada\n" SORTEADO por chave,
-- base para a busca binária dos plugins/dicionario.lua.
--
--   chave            = palavra em letras base, minúsculas, sem acento ("voce")
--   canonical        = forma canônica, preservando o acento           ("você")
--   freq_texto       = maior frequência da grafia PLANA (sem acento)
--   freq_acentuada   = idem da grafia ACENTUADA
--                      (o plugin compara p/ não "corrigir" forma real e comum)
--
-- Entrada aceita 3 formatos de palavras:
--   * "palavra 12345"              lista de frequência ("FrequencyWords")
--   * "palavra/BZ" ou "palavra/ü"  dicionário Hunspell .dic (flags pós "/")
--   * "palavra"                    lista pura (uma por linha)
--
-- usa: lua5.1 scripts/gera_dicionario.lua <entrada> <saida.dat> [<saida.lua>]
--
-- A saída é ordenada lexicograficamente pela chave (só a-z) para que o plugin
-- possa "cortar o dicionário pela metade" com busca binária por prefixo do que
-- o usuário já digitou. Com um 3º argumento, o mesmo índice também é gravado
-- como módulo Lua (plugins/dicionario_dados.lua), embutido nos plugins para o
-- aparelho nunca precisar baixar nada do :dict.
local entrada, saida = arg[1], arg[2]
if not (entrada and saida) then
  io.stderr:write("uso: lua5.1 scripts/gera_dicionario.lua <in.dic> <out.dat>\n")
  os.exit(1)
end

local BASE = {}
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
  BASE[p[1]] = p[2]
end

-- Só letras (acentuadas ou não) entram; hífens, números e símbolos ficam fora
-- (não se corrige "a-aminase" nem "3D").
local LETRAS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  .. "àáâãäåçèéêëìíîïñòóôõöùúûüÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜ"

local f = assert(io.open(entrada, "rb"))
local corpo = f:read("*a")
f:close()

-- palaavra -> (palavra, frequência). Formatos:
--   "palavra 12345"   lista de frequência (subtitle-corpus: melhor indicador
--                     da forma real em uso — "ideia" > "idéia"; "não" > "nao")
--   "palavra/BG"      Hunspell (sem frequência → 1)
--   "palavra"         lista pura (→ 1)
local function extrai(linha)
  local w, freq = linha:match("^(%S+)%s+([%d%.]+)%s*$")
  if w then return w, tonumber(freq) end
  w = linha:match("^([^/]+)")
  return (w ~= "" and w or nil), 1
end

local mapa = {}
local total = 0
for linha in corpo:gmatch("[^\r\n]+") do
  local w, freq = extrai(linha)
  if w and freq then
    w = w:lower()
    freq = tonumber(freq) or 1
    if not w:find("[^" .. LETRAS .. "]") then
      total = total + 1
      local chave = (w:gsub("([\194-\255][\128-\191]*)",
          function(c) return BASE[c] or c end)):lower()
      local g = mapa[chave]
      if not g then
        g = { canon = nil, freq = 0, fp = 0, fa = 0 }
        mapa[chave] = g
      end
      local acc = w ~= chave
      -- máxima frequência vence (forma realmente usada na ortografia atual);
      -- empate prefere a acentuada ("você" contra "voce", ambas raras).
      if not g.canon or freq > g.freq or (freq == g.freq and acc and not g.acc) then
        g.canon, g.freq, g.acc = w, freq, acc
      end
      -- guarda a maior frequência de cada GRAFIA (plana vs acentuada): o plugin
      -- usa p/ não "corrigir" formas reais e comuns (esta, têm, quê, que...).
      if acc then
        if freq > g.fa then g.fa = freq end
      elseif freq > g.fp then
        g.fp = freq
      end
    end
  end
end

local ordenado = {}
for chave, e in pairs(mapa) do
  ordenado[#ordenado + 1] = { chave, e.canon, e.fp, e.fa }
end
table.sort(ordenado, function(a, b)
  if a[1] ~= b[1] then return a[1] < b[1] end
  return a[2] < b[2]
end)

local out = assert(io.open(saida, "wb"))
local eh_acentuada = 0
for _, e in ipairs(ordenado) do
  out:write(e[1], "\t", e[2], "\t", e[3], "\t", e[4], "\n")
  if e[1] ~= e[2] then eh_acentuada = eh_acentuada + 1 end
end
out:close()

io.write(("ok: %d linhas sorteadas (%d únicas, %d com acento) -> %s\n")
  :format(#ordenado, total, eh_acentuada, saida))

-- Opcional: o mesmo índice como módulo Lua embutido (sem download no aparelho).
if arg[3] then
  local outlua = assert(io.open(arg[3], "wb"))
  outlua:write("-- dicionario_dados.lua — índice do :dict (GERADO). Não edite à mão.\n")
  outlua:write("-- Fonte: lista de frequência do português (hermitdave/FrequencyWords\n")
  outlua:write("-- pt_50k.txt, MIT). Formato: 'chave\\tcanonical\\tfreq_plana\\tfreq_acu'\n")
  outlua:write("-- por linha, ordenado pela chave (busca binária ao digitar).\n")
  outlua:write("-- Regenerate: lua5.1 scripts/gera_dicionario.lua <entrada> <out.dat> <saida.lua>\n")
  outlua:write("return [===[\n")
  for _, e in ipairs(ordenado) do
    outlua:write(e[1], "\t", e[2], "\t", e[3], "\t", e[4], "\n")
  end
  outlua:write("]===]\n")
  outlua:close()
  io.write(("ok: módulo Lua -> %s\n"):format(arg[3]))
end