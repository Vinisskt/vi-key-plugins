-- cat.lua — :cat [caminho...] — mostra o conteúdo de um arquivo.
--   :cat <caminho>        vê o arquivo direto (vários args = vários arquivos)
--   :cat                  escolhe o arquivo pelo explorador do fzf (âncora) e vê
-- API:
--   cat.view(caminho...)  mostra o(s) caminho(s) (igual a :cat com argumentos)
--
-- Curto -> statusbar; longo (>300 chars) -> página rolável (vim.page).
local termux = require("termux")
local sh = require("shell")
local fzf = require("fzf")

local M = {}

function M.view(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = sh.shq(select(i, ...))
  end
  termux.run({ "cat " .. table.concat(parts, " ") })
end

function M.run(args)
  if #args == 0 then
    fzf.open_explorer(nil, function(path)
      M.view(path)
    end)
    return
  end
  M.view(unpack(args))
end

vim.register("cat", function(...) M.run({...}) end)
return M