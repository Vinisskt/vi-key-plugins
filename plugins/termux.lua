-- termux.lua — integração teclado <-> Termux: a porta para as ferramentas
-- Linux no Android. Módulo único, carregado por init.lua (require("termux")).
--   :termux <comando>   executa no Termux e mostra a saída na hora
--   :termux             sem argumento: mostra a última saída salva
--   :$                  atalho == :termux
--   :->                 atalho para mostrar a última saída
-- Requer o daemon ipc-loop.lua rodando no Termux (veja :help termux).
-- O teclado nunca trava: nada de os.execute aqui — só lê/escreve arquivos em
-- keyboard-lua/data (cmd -> daemon, out <- daemon) com espera curta limitada
-- por TEMPO REAL (os.time; os.clock mede CPU e subestima). Resultados curtos
-- (<=300) na statusbar; longos abrem uma página rolável (vim.page).
local DATA = "/sdcard/keyboard-lua/data"

local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ---- Acompanhamento ao vivo de comandos longos (pkg upgrade, ping, ...) ----
-- Requer vim.interval (teclados novos); sem a API, degrada para o modo
-- estatico ("termux processando..." + :->).
local follow_handle = nil
local follow_last = nil

local function tidy(s)
  return s and s:gsub("%s+$", "") or ""
end

local function follow_tick()
  local out = tidy(read_file(DATA .. "/out") or "")
  local done = read_file(DATA .. "/busy") == nil and read_file(DATA .. "/cmd") == nil
  if out ~= follow_last then
    follow_last = out
    vim.page(out == "" and "(aguardando saída...)" or out)
  end
  if done then
    vim.clear_interval(follow_handle)
    follow_handle = nil
    return
  end
  -- Daemon morreu no meio do comando? (busy preso sem heartbeat) -> avisa e para.
  local hb = tonumber(read_file(DATA .. "/heartbeat")) or 0
  local last = tonumber(read_file(DATA .. "/last-start")) or 0
  local now = os.time()
  if now - hb > 6 and now - last > 6 then
    vim.clear_interval(follow_handle)
    follow_handle = nil
    vim.page(out .. "\n\n(daemon sem resposta — comando pode ter morrido)")
  end
end

local function follow_stop()
  if follow_handle then
    vim.clear_interval(follow_handle)
    follow_handle = nil
  end
end

local function follow_start()
  if not vim.interval then return end
  follow_stop()
  follow_last = nil
  vim.page("(aguardando saída...)\n")
  follow_handle = vim.interval(600, follow_tick)
end

-- Roda um comando e devolve a saída como texto (nil se sem-resposta). NÃO
-- mostra nada — o chamador decide (usado por tr.lua p/ capturar o resultado).
function M.exec(input)
  local args = input
  if type(input) ~= "table" then args = { input } end
  local cmd = table.concat(args, " ")
  if cmd == "" then return nil end
  local tmp = DATA .. "/cmd.tmp"
  local f = io.open(tmp, "w")
  if not f then
    vim.status("falta data/ (rode ipc-loop.lua no Termux)")
    return nil
  end
  f:write(cmd .. "\n")
  f:close()
  os.remove(DATA .. "/cmd")
  os.rename(tmp, DATA .. "/cmd")
  follow_stop()
  local t0 = os.time()
  while os.time() - t0 < 6 do
    if read_file(DATA .. "/busy") == nil and read_file(DATA .. "/cmd") == nil then
      return tidy(read_file(DATA .. "/out") or "")
    end
  end
  local hb = tonumber(read_file(DATA .. "/heartbeat")) or 0
  local last = tonumber(read_file(DATA .. "/last-start")) or 0
  local now = os.time()
  if now - last <= 8 or now - hb <= 8 then
    vim.status("termux processando — acompanhando a saída...")
    follow_start()
  else
    vim.status("termux sem resposta (rode ipc-loop.lua no Termux)")
  end
  return nil
end

function M.show()
  local f = io.open(DATA .. "/out", "r")
  if not f then
    vim.status("(sem saída ainda — envie um comando com :termux)")
    return
  end
  local s = f:read("*a")
  f:close()
  s = s and s:gsub("%s+$", "") or ""
  if s == "" then
    vim.status("(vazio)")
    return
  end
  if #s > 300 then
    vim.page(s)
  else
    vim.status(s)
  end
end

function M.run(input)
  -- Aceita uma tabela de argumentos ({...}) ou um script único.
  local args = input
  if type(input) ~= "table" then args = { input } end
  local cmd = table.concat(args, " ")
  if cmd == "" then
    M.show()
    return
  end
  local tmp = DATA .. "/cmd.tmp"
  local f = io.open(tmp, "w")
  if not f then
    vim.status("falta data/ (rode ipc-loop.lua no Termux)")
    return
  end
  f:write(cmd .. "\n")
  f:close()
  os.remove(DATA .. "/cmd")
  os.rename(tmp, DATA .. "/cmd")
  follow_stop()

  -- Espera o daemon tomar o cmd (mv cmd -> busy; timeout ~3s de tempo real).
  -- "concluído" = cmd e busy ausentes; busy presente = comando em execução.
  local t0 = os.time()
  while os.time() - t0 < 3 do
    if read_file(DATA .. "/busy") == nil and read_file(DATA .. "/cmd") == nil then
      M.show()
      return
    end
  end
  -- Ainda pendente: diferencia comando longo (daemon trabalhou nele) de
  -- daemon morto. last-start é gravado pelo daemon ao começar a executar.
  local hb = tonumber(read_file(DATA .. "/heartbeat")) or 0
  local last = tonumber(read_file(DATA .. "/last-start")) or 0
  local now = os.time()
  if now - last <= 4 or now - hb <= 4 then
    vim.status("termux processando — acompanhando a saída...")
    follow_start()
  else
    vim.status("termux sem resposta (rode ipc-loop.lua no Termux)")
  end
end

vim.register("termux", function(...) M.run({...}) end)
vim.register("$", function(...) M.run({...}) end)
vim.register("->", function() M.show() end)
return M