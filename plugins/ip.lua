-- ip.lua — :ip — endereços de rede dos interfaces.
-- Usa ifconfig (sem dependência extra); na falta, tenta `ip -4 addr`.
local termux = require("termux")

local M = {}

function M.run()
  termux.run(
      "ifconfig 2>/dev/null | grep -E '(^[a-z]|inet )' || ip -4 addr 2>/dev/null")
end

vim.register("ip", function() M.run() end)
return M