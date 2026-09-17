#!/usr/bin/env luajit
-- test/grafo.lua — teste do grafo palavra→palavra derivado do modelo embutido.
-- Sem GRAFO_SEED manual. As arestas vêm de P(alvo|ctx) nos bigramas e o
-- gênero é derivado de P(palavra|"a"/"uma") vs P(palavra|"o"/"um").
package.path = "./?.lua;./plugins/?.lua;" .. package.path
local mod = require("plugins.dicionario")
local ok, err = pcall(mod.carregar_embutido)
if not ok then io.stderr:write("carregar_embutido: " .. tostring(err) .. "\n"); os.exit(1) end
local d = assert(mod.carregar_embutido(), "dicionário embutido indisponível")
local modelo = assert(mod.carregar_modelo_embutido(), "modelo embutido indisponível")

local function fila(ws)
  local t = {}
  for w in ws:gmatch("%S+") do t[#t+1] = mod.sem_acento(w) end
  return t
end

local function test(nome, ok, info)
  io.write(ok and "  ok  " or "  FALHA ")
  io.write(string.format("%-52s %s\n", nome, info or ""))
  return ok
end

local pass, fail = 0, 0
local function T(nome, ok, info)
  if ok then pass = pass + 1 else fail = fail + 1 end
  test(nome, ok, info)
end

print("== grafo derivado do modelo (sem seed manual) ==")

-- 1) Arestas reais: P(carta|"uma") = 197 (top alvo)
local v1 = mod.voto_grafo(modelo, {"uma"}, "carta")
T("voto_grafo(uma → carta) > 0",
  v1 and v1 > 0,
  string.format("got=%s", tostring(v1)))

-- 2) P(livro|"um") = 832 (top alvo)
local v2 = mod.voto_grafo(modelo, {"um"}, "livro")
T("voto_grafo(um → livro) > 0",
  v2 and v2 > 0,
  string.format("got=%s", tostring(v2)))

-- 3) P(historia|"uma") = 1400
local v3 = mod.voto_grafo(modelo, {"uma"}, "historia")
T("voto_grafo(uma → historia) > 0",
  v3 and v3 > 0,
  string.format("got=%s", tostring(v3)))

-- 4) Gênero: "uma" + carta (F) vs "o" + carta (F)
local vf = mod.voto_grafo(modelo, {"uma"}, "carta")
local vm = mod.voto_grafo(modelo, {"o"}, "carta")
T("gênero: voto(uma→carta) > voto(o→carta)",
  (vf or 0) > (vm or 0),
  string.format("fem=%s masc=%s", tostring(vf), tostring(vm)))

-- 5) Gênero: "um" + livro (M) vs "uma" + livro (M)
local vm2 = mod.voto_grafo(modelo, {"um"}, "livro")
local vf2 = mod.voto_grafo(modelo, {"uma"}, "livro")
T("gênero: voto(um→livro) > voto(uma→livro)",
  (vm2 or 0) > (vf2 or 0),
  string.format("masc=%s fem=%s", tostring(vm2), tostring(vf2)))

-- 6) Palavras sem aresta: "corte" não tem P(faca|"corte") no modelo
--    (top-32 de "corte" não inclui faca)
local v4 = mod.voto_grafo(modelo, {"corte"}, "faca")
T("sem aresta: voto(corte→faca) == nil",
  v4 == nil,
  string.format("got=%s", tostring(v4)))

-- 7) Palavras de função não votam: "com" e "uma" filtradas como origem
local v5 = mod.voto_grafo(modelo, {"com", "uma"}, "carta")
T("palavras de função não votam",
  v5 == nil or v5 <= 0,
  string.format("got=%s", tostring(v5)))

-- 8) faa + contexto: sem aresta no modelo → nil (comportamento honesto)
local v6 = mod.voto_grafo(modelo, {"uma", "com", "cortei"}, "faca")
T("faa sem aresta no modelo → nil",
  v6 == nil,
  string.format("got=%s", tostring(v6)))

-- 9) Palavra viva preservada: "faca" como chave = canon → nil
local r9 = mod.corrigir_palavra(d, "faca")
T("faca (palavra viva) → nil preservada",
  r9 == nil,
  string.format("got=%s", tostring(r9)))

-- 10) faa sozinho: sem contexto → nil (preserva)
local r10 = mod.corrigir_palavra(d, "faa")
T("faa sozinho → nil (preserva)",
  r10 == nil,
  string.format("got=%s", tostring(r10)))

-- 11) Gênero derivado do modelo: verificar se carta é F e livro é M
local gen_carta = modelo.genero and modelo.genero["carta"]
local gen_livro = modelo.genero and modelo.genero["livro"]
T("gênero derivado: carta=F",
  gen_carta == "F",
  string.format("got=%s", tostring(gen_carta)))
T("gênero derivado: livro=M",
  gen_livro == "M",
  string.format("got=%s", tostring(gen_livro)))

-- 12) voto_grafo com decaimento: fila mais longa = voto menor
local v7a = mod.voto_grafo(modelo, {"uma"}, "carta")
local v7b = mod.voto_grafo(modelo, {"um", "que", "ela", "uma"}, "carta")
T("decaimento: voto(uma→carta) >= voto(fila longa→carta)",
  (v7a or 0) >= (v7b or 0),
  string.format("curta=%s longa=%s", tostring(v7a), tostring(v7b)))

-- 13) Grafo inverso: verificar que existe
T("modelo tem grafo inverso",
  modelo.inverso ~= nil and type(modelo.inverso) == "table",
  string.format("got=%s", tostring(modelo.inverso)))

-- 14) Gênero derivado: verificar que existe
T("modelo tem tabela de gênero",
  modelo.genero ~= nil and type(modelo.genero) == "table",
  string.format("got=%s", tostring(modelo.genero)))

print(string.format("\n== %d/%d passaram ==", pass, pass + fail))
os.exit(fail > 0 and 1 or 0)
