-- ps.lua — :ps — lista processos (pid + comando) no fzf e PARAM o escolhido.
--   ex.: um apt travado, um app que consumiu tudo -> Enter no pid mata.
--   CUIDADO: :ps é uma âncora de matar — Enter executa kill <pid> na hora.
local termux = require("termux")
local fzf = require("fzf")

local M = {}

function M.run(args)
  if #args > 0 then
    vim.status("uso: :ps  (Enter no processo executa kill <pid>)")
    return
  end
  fzf.run({ "ps", "-A" }, function(line)
    local pid = line:match("(%d+)")
    if not pid or pid == "1" then
      vim.status(":ps — linha sem pid")
      return
    end
    termux.run({ "kill " .. pid })
    vim.status(":ps → kill " .. pid)
  end)
end

vim.register("ps", function(...) M.run({...}) end)
return M