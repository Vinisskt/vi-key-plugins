-- which.lua — :which <programa...> — mostra o caminho de cada executável.
--   ex.: :which lua5.1 ffmpeg python
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  if #args == 0 then
    vim.status("uso: :which <programa>")
    return
  end
  local parts = {}
  for i = 1, #args do parts[#parts + 1] = sh.shq(args[i]) end
  termux.run({ "command -v " .. table.concat(parts, " ") })
end

vim.register("which", function(...) M.run({...}) end)
return M