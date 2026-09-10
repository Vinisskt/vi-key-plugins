-- pkg.lua — :pkg <op> [alvos] — gerenciador de pacotes do Termux.
--   :pkg search <termo>        procura pacotes
--   :pkg install <pkg...>      instala (com -y, sem confirmar)
--   :pkg remove <pkg...>       desinstala
--   :pkg upgrade               atualiza todos
--   :pkg list                  pacotes instalados
--   :pkg info <pkg>            detalhes de um pacote
local termux = require("termux")
local sh = require("shell")

local HELP = "uso: :pkg search|install|remove|upgrade|list|info <alvos>"

local M = {}

function M.run(args)
  if #args == 0 then
    vim.status(HELP)
    return
  end
  local op = args[1]:lower()
  local rest = {}
  for i = 2, #args do rest[#rest + 1] = sh.shq(args[i]) end
  local targets = table.concat(rest, " ")
  if targets ~= "" then targets = " " .. targets end
  if op == "search" then
    termux.run({ "pkg search" .. targets })
  elseif op == "install" then
    termux.run({ "pkg install -y" .. targets })
  elseif op == "remove" or op == "uninstall" or op == "del" then
    termux.run({ "pkg uninstall -y" .. targets })
  elseif op == "upgrade" then
    termux.run({ "pkg upgrade -y" })
  elseif op == "list" then
    termux.run({ "pkg list-installed" })
  elseif op == "info" then
    termux.run({ "pkg show" .. targets })
  else
    vim.status(HELP)
  end
end

vim.register("pkg", function(...) M.run({...}) end)
return M