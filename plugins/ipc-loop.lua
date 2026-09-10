-- ipc-loop.lua — ponte vi-key <-> Termux, em Lua.
-- Um mesmo módulo, dois papéis:
--   * DAEMON  (processo separado no Termux): lua5.1 plugins/ipc-loop.lua --daemon
--     mantido pelo serviço runit vk-ipc. Loop infinito: quando aparece
--     keyboard-lua/data/cmd, executa o comando (shell) gravando a saída em
--     data/out e apaga o cmd. Nunca roda na thread do teclado — aqui
--     os.execute/sleep são de um processo próprio e não travam o IME.
--   * PLUGIN  (no teclado): require("ipc-loop") no init.lua. Não roda loop
--     nenhum (travaria a UI); só registra o comando :ipcloop — status do
--     daemon via heartbeat — e retorna o módulo.
local DIR = "/sdcard/keyboard-lua"
local DATA = DIR .. "/data"
local BASH = "/data/data/com.termux/files/usr/bin/bash"

local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

function M.status()
  local hb = tonumber(read_file(DATA .. "/heartbeat")) or 0
  local age = os.time() - hb
  if hb > 0 and age <= 4 then
    return "ipc ativo (heartbeat " .. age .. "s)"
  end
  return "ipc parado — no Termux rode: sv start vk-ipc"
end

function M.run()
  os.execute("mkdir -p " .. DATA)
  os.execute("termux-wake-lock")
  while true do
    write_file(DATA .. "/heartbeat", tostring(os.time()))
    if read_file(DATA .. "/stop") then
      os.remove(DATA .. "/stop")
      return
    end
    -- Toma um comando pendente (atômico) e o executa. O arquivo [cmd] some na
    -- hora da tomada (fila segura contra sobreposição), mas o [busy] só some
    -- quando o comando termina — é o sinal de "concluído" para o teclado.
    if read_file(DATA .. "/cmd") ~= nil and read_file(DATA .. "/busy") == nil then
      if os.rename(DATA .. "/cmd", DATA .. "/busy") then
        write_file(DATA .. "/out", "")
        -- Timestamp de início do comando: permite ao teclado distinguir
        -- "comando longo em andamento" de "daemon morto".
        write_file(DATA .. "/last-start", tostring(os.time()))
        os.execute(BASH .. " '" .. DATA .. "/busy' > '" .. DATA .. "/out' 2>&1")
        os.remove(DATA .. "/busy")
      end
    end
    os.execute("sleep 0.3")
  end
end

local daemon = (_G.arg ~= nil and _G.arg[1] == "--daemon")
if daemon then
  M.run()
else
  vim.register("ipcloop", function()
    vim.status(M.status())
  end)
end
return M