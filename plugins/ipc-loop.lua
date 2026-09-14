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
-- O FIFO/worker vivem aqui (o /sdcard é FUSE e não suporta FIFO); a
-- interface com o teclado segue por arquivos em DATA.
local VAR = "/data/data/com.termux/files/usr/var/vk-ipc"
local FIFO = VAR .. "/fifo"
-- Token p/ achar o worker em pkill (aparece no argv do bash persistente).
local WORKER_TOKEN = "vk-ipc-worker"

local M = {}

-- Gancho p/ testes: aponta DATA/VAR (diretórios de fila e worker) para pastas
-- temporárias sem tocar no fluxo da ponte.
function M.set_env(data_dir, var_dir)
  if data_dir then DATA = data_dir end
  if var_dir then VAR, FIFO = var_dir, var_dir .. "/fifo" end
end

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

-- ---- Worker persistente (bash nasce UMA vez, nao por comando) ----
-- O grosso da latencia era o spawn de um bash novo a cada comando. Agora um
-- unico bash lê do FIFO o caminho do arquivo [busy], executa seu conteudo
-- (eval: multi-linha ok) jogando a saida em data/out e so entao remove o
-- [busy] — o sinal de "concluido" que o teclado espera. Sem spawn por comando.
-- O loop vive num ARQUIVO (data/worker-loop.sh) para nao lidar com aspas
-- aninhadas de shell -c.
local function worker_start()
  os.execute("pkill -f " .. WORKER_TOKEN .. " 2>/dev/null")
  os.remove(FIFO)
  os.execute("mkdir -p " .. VAR)
  os.execute("mkfifo " .. FIFO)
  local script = DATA .. "/worker-loop.sh"
  local loop = "while true; do exec 3< '" .. FIFO .. "' 2>/dev/null || break; " ..
    "while read -r b <&3; do cd \"$HOME\" 2>/dev/null || cd /; " ..
    "eval \"$(cat $b)\" > '" .. DATA .. "/out' 2>&1; rm -f $b; done; done\n"
  write_file(script, loop)
  -- argv com TOKEN como primeiro argumento (pkill -f o encontra).
  local cmd = BASH .. " --noprofile --norc '" .. script .. "' " ..
    WORKER_TOKEN .. " < " .. FIFO .. " >/dev/null 2>&1 & echo $!"
  local pid = io.popen(cmd, "r")
  local p = pid and pid:read("*l")
  if pid then pid:close() end
  if p and p ~= "" then write_file(VAR .. "/worker.pid", p) end
end

local function worker_alive()
  local f = io.open(VAR .. "/worker.pid", "r")
  local p = f and f:read("*l")
  if f then f:close() end
  if not p or p == "" then return false end
  local pg = io.popen("kill -0 " .. p .. " 2>/dev/null && echo ok", "r")
  local ok = pg and pg:read("*l")
  if pg then pg:close() end
  return ok == "ok"
end

-- Envia o caminho do [busy] pro worker (o write no FIFO só desbloqueia quando
-- o bash estiver lendo; por isso a checagem de vida antes).
local function worker_push(busy)
  if not worker_alive() then worker_start() end
  local f = io.open(FIFO, "w")
  if not f then return false end
  f:write(busy .. "\n")
  f:close()
  return true
end

local function worker_stop()
  os.execute("pkill -f " .. WORKER_TOKEN .. " 2>/dev/null")
  os.remove(FIFO)
end

function M.status()
  local hb = tonumber(read_file(DATA .. "/heartbeat")) or 0
  local age = os.time() - hb
  if hb > 0 and age <= 4 then
    return "ipc ativo (heartbeat " .. age .. "s, worker " ..
      (worker_alive() and "ok" or "morto") .. ")"
  end
  return "ipc parado — no Termux rode: sv start vk-ipc"
end

function M.run()
  os.execute("mkdir -p " .. DATA)
  os.execute("termux-wake-lock")
  worker_start()
  while true do
    write_file(DATA .. "/heartbeat", tostring(os.time()))
    if read_file(DATA .. "/stop") then
      os.remove(DATA .. "/stop")
      worker_stop()
      return
    end
    -- Toma um comando pendente (atômico) e o repassa ao worker. O [cmd] some
    -- na tomada (fila segura contra sobreposição); o [busy] só some quando o
    -- worker termina de executar — é o sinal de "concluído" para o teclado.
    if read_file(DATA .. "/cmd") ~= nil and read_file(DATA .. "/busy") == nil then
      if os.rename(DATA .. "/cmd", DATA .. "/busy") then
        -- Timestamp de início do comando: permite ao teclado distinguir
        -- "comando longo em andamento" de "daemon morto".
        write_file(DATA .. "/last-start", tostring(os.time()))
        worker_push(DATA .. "/busy")
      end
    end
    os.execute("sleep 0.1")
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