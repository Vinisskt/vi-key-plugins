-- weather.lua — :weather [cidade] — previsão do tempo (via wttr.in; precisa de curl).
--   :weather             previsão local (com base no seu IP)
--   :weather Sao Paulo   cidade específica (espaço vira +)
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  local q = (args[1] ~= nil) and table.concat(args, " "):gsub("%s+", "+") or ""
  -- URL inteira sob shq: cidade com aspas/;$ trocaria de contexto (injeção).
  termux.run({ "curl -s -m 12 " .. sh.shq("wttr.in/" .. q .. "?format=%l:+%c+%t+%w") })
end

vim.register("weather", function(...) M.run({...}) end)
return M