-- man.lua — :man <comando> [seção] — página de manual do Linux no teclado.
--   ex.: :man ls   :man 5 crontab
--   A saída é longa; o termux.run mostra na statusbar (<300) ou abre página.
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  if #args == 0 then
    vim.status("uso: :man <comando> [seção]")
    return
  end
  local parts = {}
  for i = 1, #args do parts[#parts + 1] = sh.shq(args[i]) end
  termux.run({ "man " .. table.concat(parts, " ") })
end

vim.register("man", function(...) M.run({...}) end)
return M