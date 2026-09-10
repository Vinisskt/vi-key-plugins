-- sysinfo.lua — :sysinfo [net|cpu|mem|disk] — situação do sistema.
--   :sysinfo        tudo (cpu, memória, disco, rede)
--   :sysinfo mem    só memória    :sysinfo disk  só disco
--   :sysinfo cpu    só cpu       :sysinfo net   só rede
-- Monta um mini script bash que o daemon executa como um só comando.
local termux = require("termux")

local M = {}

local sections = {
  net  = "echo '== rede =='; ifconfig 2>/dev/null || ip -4 addr 2>/dev/null",
  cpu  = "echo '== cpu =='; grep -m1 'model name' /proc/cpuinfo 2>/dev/null; "
      .. "grep -c processor /proc/cpuinfo | awk '{ print \"núcleos: \" $1 }'",
  mem  = "echo '== memória =='; free -h 2>/dev/null || head -3 /proc/meminfo",
  disk = "echo '== disco =='; df -h / /data /sdcard 2>/dev/null || df -h",
}

function M.run(args)
  local section = (args[1] ~= nil) and args[1]:lower() or ""
  local script
  if sections[section] ~= nil then
    script = sections[section]
  else
    script = table.concat({ sections.cpu, sections.mem, sections.disk, sections.net }, "\n")
  end
  termux.run({ script })
end

vim.register("sysinfo", function(...) M.run({...}) end)
return M