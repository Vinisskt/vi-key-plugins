-- prova_janela.lua — prova a camada 1 (janela longa) no runtime real:
-- corrigir_palavra com `fila` decide homógrafas pela janela (backoff das
-- B/T atuais + decaimento), e a passada sem fila continua idêntica.
package.path = "./?.lua;./plugins/?.lua;" .. package.path
local F = { mod = require("plugins.dicionario") }
if not F.mod.carregar_dados then F.mod = require("plugins.dicionario_modelo") end
local ok, dados = pcall(F.mod.carregar_dados, "plugins/dicionario_dados.lua")
if not ok then
  io.write("SEM DADOS: " .. tostring(dados) .. "\n"); os.exit(0)
end
F.mod.setup({ dados_dir = "plugins", aviso = false, depurar = false })
F.mod.carregar_modelo_embutido()
local sem_acento = F.mod.sem_acento
local sl = { "ele fabrica" , "a fabrica", "ele fabrica peças", "a fabrica fechou" }
local n = 0
for _, t in ipairs(sl) do
  local toks = {}
  for tk in t:gmatch("[A-Za-zÀ-ÿçÇ']+") do toks[#toks + 1] = tk end
  -- fila (mais recente em 1): as N-1 palavras ANTES do alvo
  for i = 1, #toks do
    local fila = {}
    for k = i - 1, math.max(1, i - 1), -1 do
      if k >= 1 then fila[#fila + 1] = sem_acento(toks[k]) end
      if #fila >= 2 then break end
    end
    local r = F.mod.corrigir_palavra(F.d, toks[i], fila[2], fila[1], fila)
    n = n + 1
    io.write(string.format("%2d. %q fila={%s} -> %s\n", n, toks[i],
      table.concat(fila, ","), tostring(r)))
  end
end
print("janela_ctx=" .. tostring((F.mod.get_config and F.mod.get_config().janela_ctx) or "?"))
