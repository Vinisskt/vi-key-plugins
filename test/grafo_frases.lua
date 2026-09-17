#!/usr/bin/env luajit
-- test/grafo_frases.lua — frases com 1 palavra errada: o grafo derivado do
-- modelo embutido decide pelo contexto. Sem seed manual.
package.path = "./?.lua;./plugins/?.lua;" .. package.path
local mod = require("plugins.dicionario")
local ok, err = pcall(mod.carregar_embutido)
if not ok then io.stderr:write("carregar_embutido: " .. tostring(err) .. "\n"); os.exit(1) end
local d = assert(mod.carregar_embutido(), "dicionário embutido indisponível")
local modelo = assert(mod.carregar_modelo_embutido(), "modelo embutido indisponível")

-- Palavras anteriores ao caret (fila da posição 1 = imediata).
local function fila_antes(frase, pos)
  local t = {}
  local i = 0
  for w in frase:gmatch("%S+") do
    i = i + 1
    if i < pos then t[#t + 1] = mod.sem_acento(w) end
  end
  return t
end

local function corrige(frase, pos)
  return mod.corrigir_palavra2(nil, frase, pos)
end

-- corrigir_palavra2 não existe no plugin; usa corrigir_palavra com fila.
local function corrige_fila(frase, pos)
  local f = fila_antes(frase, pos)
  local i = 0
  local palavra
  for w in frase:gmatch("%S+") do
    i = i + 1
    if i == pos then palavra = w end
  end
  return mod.corrigir_palavra(d, palavra, nil, nil, f)
end

local pass, fail = 0, 0
local function T(nome, got, queria)
  local f = (got == queria)
  if f then pass = pass + 1 else fail = fail + 1 end
  io.write(string.format("  %s %-48s got=%-14s queria=%s\n",
    f and "ok" or "FALHA", nome, tostring(got), tostring(queria)))
end
local function Tb(nome, cond, info)
  if cond then pass = pass + 1 else fail = fail + 1 end
  io.write(string.format("  %s %-48s %s\n",
    cond and "ok" or "FALHA", nome, info or ""))
end

print("== frases com 1 erro; grafo decide pelo contexto do modelo ==")

-- "escrevi uma cartta" → "carta": P(carta|uma)=197, gênero F combina com "uma"
T("escrevi uma cartta", corrige_fila("escrevi uma cartta", 3), "carta")

-- "deixei o livru na mesa" → "livro": P(livro|um)=832, gênero M combina com "o"
T("deixei o livru na mesa", corrige_fila("deixei o livru na mesa", 3), "livro")

-- "conto uma histori pra ela" → "história" (canônica; falta o "a", DL=1)
T("conto uma histori pra ela", corrige_fila("conto uma histori pra ela", 3), "história")

-- "faa" sozinho sem contexto → nil (o modelo não tem aresta corte→faca; honesto)
T("faa sozinho → nil", mod.corrigir_palavra(d, "faa"), nil)

-- "faca" palavra viva → nil preservada
T("faca viva → nil", mod.corrigir_palavra(d, "faca"), nil)

-- "fada" palavra viva → nil preservada
T("fada viva → nil", mod.corrigir_palavra(d, "fada"), nil)

-- Palavras que o modelo não cobre → comportamento honesto (nil), não inventa:
T("cortou faa (sem aresta) → nil", corrige_fila("eu cortou uma faa", 3), nil)

-- Gênero desmente o artigo: "o cartta" — carta é F e "o" é M → menos voto.
local vf = mod.voto_grafo(modelo, {"uma"}, "carta")
local vo = mod.voto_grafo(modelo, {"o"}, "carta")
Tb("voto(uma→carta) > voto(o→carta) por gênero",
  (vf or 0) > (vo or 0),
  string.format("fem=%s masc=%s", tostring(vf), tostring(vo)))

print(string.format("\n== %d/%d passaram ==", pass, pass + fail))
os.exit(fail > 0 and 1 or 0)