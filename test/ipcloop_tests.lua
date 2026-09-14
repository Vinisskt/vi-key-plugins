-- ipcloop_tests.lua — cobertura do :ipcloop (lado PLUGIN do ipc-loop.lua).
-- O daemon (--daemon) exige pkill/mkfifo num Termux real; aqui testamos o que
-- roda no teclado: M.status() lendo heartbeat/worker.pid de pastas temporárias
-- via M.set_env, e o registro do comando na thread da UI.
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local uid = 0
local function tmpdir(prefix)
  uid = uid + 1
  local d = "/tmp/vk-ipc-" .. prefix .. "-" .. tostring(os.time()) .. "-" .. tostring(uid)
  os.execute("mkdir -p '" .. d .. "'")
  return d
end

local function write(p, s)
  local f = assert(io.open(p, "w"))
  f:write(s)
  f:close()
end

local function newdaemon()
  local d, v = tmpdir("data"), tmpdir("var")
  local t = sandbox.load("ipc-loop", { deps = sandbox.default_deps() })
  t.ret.set_env(d, v)
  t._data, t._var = d, v
  return t
end

-- PID vivo de verdade p/ simular o worker (sleep em background 30s).
local function live_pid()
  local pg = io.popen("sleep 30 & echo $!")
  local pid = pg and pg:read("*l") or ""
  if pg then pg:close() end
  return pid
end

T.section("A. registro do comando (lado plugin)")
local t = newdaemon()
T.is(":ipcloop registrado", sandbox.command(t, "ipcloop") ~= nil)

T.section("B. sem heartbeat => ipc parado")
T.eq("status parado", t.ret.status(), "ipc parado — no Termux rode: sv start vk-ipc")

T.section("C. heartbeat fresco + worker vivo => ipc ativo")
local t2 = newdaemon()
write(t2._data .. "/heartbeat", tostring(os.time()))
write(t2._var .. "/worker.pid", live_pid())
local s = t2.ret.status()
T.is("ativo no header", s:find("ipc ativo") ~= nil)
T.is("worker ok", s:find("worker ok") ~= nil)

T.section("D. heartbeat fresco + worker morto => ativo c/ worker morto")
local t3 = newdaemon()
write(t3._data .. "/heartbeat", tostring(os.time()))
write(t3._var .. "/worker.pid", "123456789")
local s3 = t3.ret.status()
T.is("header ativo", s3:find("ipc ativo") ~= nil)
T.is("worker morto", s3:find("worker morto") ~= nil)

T.section("E. heartbeat velho => parado (mesmo com worker)")
local t4 = newdaemon()
write(t4._data .. "/heartbeat", tostring(os.time() - 10))
write(t4._var .. "/worker.pid", live_pid())
T.eq("stale => parado", t4.ret.status(), "ipc parado — no Termux rode: sv start vk-ipc")

T.section("F. worker.pid inexistente => worker morto")
local t5 = newdaemon()
write(t5._data .. "/heartbeat", tostring(os.time()))
local s5 = t5.ret.status()
T.is("sem pid => morto", s5:find("worker morto") ~= nil)

T.section("G. comando :ipcloop repassa status")
local t6 = newdaemon()
local ipcloop = sandbox.command(t6, "ipcloop")
ipcloop()
T.eq("status do comando = M.status()", t6.vim.statuses[#t6.vim.statuses], t6.ret.status())

T.done("ipcloop")