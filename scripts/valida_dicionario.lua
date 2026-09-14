-- valida_dicionario.lua — audita uma lista de palavras (freq/hunspell/plana) e
-- reporta onde há DUALIDADE de grafia: a mesma "chave" sem acento com uma forma
-- acentuada e outra sem acento. Mostra qual o gerador escolheria (por
-- frequência) para o humano conferir acentos vindos de ortografias antigas /
-- pt-PT / espanhol.
--
-- usa: lua5.1 scripts/valida_dicionario.lua <pt_50k.txt> [mín. ocorrências]
-- saída:  chave | acentuada (freq) | plana (freq) | escolhida
-- ordenada pela frequência da forma plana (palavras reais do dia-a-dia 1º).
local entrada, MIN = arg[1], tonumber(arg[2]) or 10
if not entrada then
  io.stderr:write("uso: lua5.1 scripts/valida_dicionario.lua <palavras.txt> [min-freq]\n")
  os.exit(1)
end

local BASE = {}
for _, p in ipairs({
  { "à", "a" }, { "á", "a" }, { "â", "a" }, { "ã", "a" }, { "ä", "a" }, { "å", "a" },
  { "ç", "c" }, { "è", "e" }, { "é", "e" }, { "ê", "e" }, { "ë", "e" },
  { "ì", "i" }, { "í", "i" }, { "î", "i" }, { "ï", "i" },
  { "ñ", "n" }, { "ò", "o" }, { "ó", "o" }, { "ô", "o" }, { "õ", "o" }, { "ö", "o" },
  { "ù", "u" }, { "ú", "u" }, { "û", "u" }, { "ü", "u" },
}) do BASE[p[1]] = p[2] end

-- contagens por forma real (palavra grafada) sob a mesma chave
local grupo = {} -- chave -> { palaabra -> freq }
for linha in io.open(entrada, "rb"):read("*a"):gmatch("[^\r\n]+") do
  local w, freq = linha:match("^(%S+)%s+([%d%.]+)%s*$")
  if not w then
    w = linha:match("^([^/]+)")
    freq = 1
  end
  if w and freq then
    w = w:lower()
    if not w:find("[^abcdefghijklmnopqrstuvwxyzàáâãäåçèéêëìíîïñòóôõöùúûü]") then
      local chave = (w:gsub("([\194-\255][\128-\191]*)",
          function(c) return BASE[c] or c end)):lower()
      local g = grupo[chave] or {}
      g[w] = (g[w] or 0) + (tonumber(freq) or 1)
      grupo[chave] = g
    end
  end
end

local linhas = {}
for chave, g in pairs(grupo) do
  local acentuada, f_ac, plana, f_pl = nil, 0, nil, 0
  for w, f in pairs(g) do
    local ac = w ~= chave
    if ac and (not acentuada or f > f_ac) then acentuada, f_ac = w, f end
    if not ac and (not plana or f > f_pl) then plana, f_pl = w, f end
  end
  if acentuada and plana and f_pl >= MIN then
    local escolhida = plana
    if f_ac > f_pl then escolhida = acentuada end
    linhas[#linhas + 1] = { f_pl, chave, acentuada, f_ac, plana, f_pl,
      (escolhida == plana and "plana" or "acentuada") }
  end
end
table.sort(linhas, function(a, b) return a[1] > b[1] end)

print(("duplas acentuada×plana com a plana >= %d ocorrências: %d\n"):format(MIN, #linhas))
print(("  %-22s %-24s %-10s %-24s %-10s %s"):format("chave", "aguçuada", "freq-a", "plana", "freq-p", "escolha"))
for _, l in ipairs(linhas) do
  print(("  %-22s %-24s %-10d %-24s %-10d %s"):format(l[2], l[3], l[4], l[5], l[6], l[7]))
end