-- files.lua — :files [caminho] — lista arquivos (padrão: $HOME do Termux).
--   ex.: :files /sdcard  :files ~/storage/shared/Download
local termux = require("termux")
local sh = require("shell")

local M = {}

function M.run(args)
  local arg = (args[1] ~= nil and args[1] ~= "") and table.concat(args, " ") or "$HOME"
  termux.run({ "ls -la --color=never " .. sh.shq(arg) })
end

vim.register("files", function(...) M.run({...}) end)
return M