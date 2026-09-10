-- calc.lua — :calc <expressão> — calculadora (usa o lua5.1 do Termux).
--   ex.: :calc 2+2*3  :calc math.pi  :calc math.max(3,7)+1
-- OBS: é Lua de verdade — serve também como console Lua rápido.
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  local expr = table.concat(args, " ")
  if expr == "" then
    vim.status("uso: :calc <expressão lua>  ex.: :calc 2+2*3")
    return
  end
  termux.run({ "lua5.1 -e " .. sh.shq("print(" .. expr .. ")") })
end

vim.register("calc", function(...) M.run({...}) end)
return M