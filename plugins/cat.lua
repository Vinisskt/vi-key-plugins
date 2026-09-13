-- cat.lua — :cat <caminho> — mostra o conteúdo de um arquivo.
--   ex.: :cat ~/storage/shared/Download/notas.txt  :cat /etc/hosts
--   :cat sem argumento: escolhe o arquivo pelo fzf (Enter = cat no selecionado).
-- Curto -> statusbar; longo (>300 chars) -> página rolável (vim.page).
local termux = require("termux")
local sh = require("shell")
local fzf = require("fzf")

local M = {}

function M.run(args)
  if #args == 0 then
    fzf.open_explorer(nil, function(path)
      termux.run({ "cat " .. sh.shq(path) })
    end)
    return
  end
  termux.run({ "cat " .. sh.shq(table.concat(args, " ")) })
end

vim.register("cat", function(...) M.run({...}) end)
return M