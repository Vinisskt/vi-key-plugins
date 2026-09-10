-- shell.lua — helpers p/ plugins que geram comandos para o daemon do Termux.
-- Módulo sem comandos; use require("shell"). O daemon executa o conteúdo de
-- data/cmd como script BASH, então argumentos do usuário devem ser protegidos
-- com shq() para nunca quebrar o script (nem onde o usuário apontar um
-- caminho com espaços).
local termux = require("termux")

local M = {}

-- Protege um argumento para uso literal no shell (aspas simples).
function M.shq(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Roda um script no Termux e mostra a saída (delega a :termux).
function M.run(script)
  termux.run({ script })
end

return M