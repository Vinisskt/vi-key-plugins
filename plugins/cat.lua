-- cat.lua — :cat <caminho> — mostra o conteúdo de um arquivo.
--   ex.: :cat ~/storage/shared/Download/notas.txt  :cat /etc/hosts
-- Curto -> statusbar; longo (>300 chars) -> página rolável (vim.page).
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  if #args == 0 then
    vim.status("uso: :cat <caminho>")
    return
  end
  termux.run({ "cat " .. sh.shq(table.concat(args, " ")) })
end

vim.register("cat", function(...) M.run({...}) end)
return M