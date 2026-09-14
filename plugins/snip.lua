-- snip.lua — :snip — insere um snippet salvo (Ctrl-V/autocomplete do fzf).
--   ~/.snippets tem uma entrada por linha, no formato:
--       nome<TAB>texto a ser colado no cursor
--   Escolha no fzf e Enter COLA o texto no cursor (vim.send).
local termux = require("termux")
local fzf = require("fzf")

local M = {}

function M.run(args)
  if #args > 0 then
    vim.status("uso: :snip  (edite ~/.snippets: uma 'nome<TAB>texto' por linha)")
    return
  end
  fzf.run({ "cat", '"$HOME/.snippets"' }, function(line)
    local _, _, _, texto = line:find("^(.-)\t(.*)$")
    vim.send(texto or line)
  end)
end

vim.register("snip", function(...) M.run({...}) end)
return M