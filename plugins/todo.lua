-- todo.lua — :todo — lista pessoal de tarefas (salva em $HOME/.todo.txt do Termux).
--   :todo              lista as tarefas (numeradas)
--   :todo add <texto>  adiciona uma tarefa
--   :todo del <n>      remove a tarefa n
--   :todo done <n>     marca a tarefa n como feita
local termux = require("termux")
local sh = require("shell")

local HELP = "uso: :todo [add <texto> | del <n> | done <n>]  (sem nada: lista)"
local F = "$HOME/.todo.txt"

local M = {}

function M.run(args)
  local op = (args[1] ~= nil) and args[1]:lower() or "list"
  local script
  if op == "list" then
    script = "awk '{ printf \"%2d  %s\\n\", NR, $0 }' " .. F .. " | tail -30"
  elseif op == "add" then
    local text = {}
    for i = 2, #args do text[#text + 1] = args[i] end
    if #text == 0 then
      vim.status(HELP)
      return
    end
    script = "echo " .. sh.shq(table.concat(text, " ")) .. " >> " .. F .. "\n"
        .. "awk '{ printf \"%2d  %s\\n\", NR, $0 }' " .. F .. " | tail -3"
  elseif op == "del" then
    local n = tonumber(args[2])
    if not n then
      vim.status("uso: :todo del <n>")
      return
    end
    script = "sed -i " .. n .. "d " .. F
  elseif op == "done" then
    local n = tonumber(args[2])
    if not n then
      vim.status("uso: :todo done <n>")
      return
    end
    script = "sed -i '" .. n .. "s/^/[x] /' " .. F
  else
    vim.status(HELP)
    return
  end
  termux.run({ script })
end

vim.register("todo", function(...) M.run({...}) end)
return M