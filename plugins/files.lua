-- files.lua — :files [caminho] — explorador de arquivos do fzf.
--   :files              navega a raiz do home (~)
--   :files /sdcard      navega a partir de /sdcard
-- (antes listava com ls -la na statusbar; agora o navegador fzf faz isso com
-- filtro, busca e rolagem)
local fzf = require("fzf")

local M = {}

function M.run(args)
  local arg = (args[1] ~= nil and args[1] ~= "") and table.concat(args, " ") or nil
  fzf.open_explorer(arg)
end

vim.register("files", function(...) M.run({...}) end)
return M