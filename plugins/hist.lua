-- hist.lua — :hist — re-executa um comando do histórico do shell (Ctrl-R do fzf).
--   Lista $HOME/.bash_history do mais recente (tac) para o mais antigo; o filtro
--   do fzf busca; Enter RODA a linha escolhida (crua, como command words).
local termux = require("termux")
local fzf = require("fzf")

local M = {}

function M.run(args)
  if #args > 0 then
    vim.status("uso: :hist  (o filtro do fzf já busca no histórico)")
    return
  end
  fzf.run({ "tac", '"$HOME/.bash_history"' }, function(line)
    termux.run({ line })
  end)
end

vim.register("hist", function(...) M.run({...}) end)
return M