-- ping.lua — :ping <host> — mede latência (4 tentativas).
--   ex.: :ping google.com  :ping 8.8.8.8
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  if #args == 0 then
    vim.status("uso: :ping <host>")
    return
  end
  termux.run({ "ping -c 4 -W 3 " .. sh.shq(table.concat(args, " ")) })
end

vim.register("ping", function(...) M.run({...}) end)
return M