-- battery.lua — :battery — nível e status da bateria.
-- 1) Tenta ler /sys/class/power_supply/* (alguns aparelhos permitem sem root).
-- 2) Senão, usa termux-battery-status (requer o app Termux:API +
--    `pkg install termux-api`). Mostra um aviso claro se faltar.
local termux = require("termux")

local M = {}

function M.run()
  termux.run(
      "B=\"\"\n" ..
      "for p in /sys/class/power_supply/*; do\n" ..
      "  [ \"$(cat $p/type 2>/dev/null)\" = \"Battery\" ] && B=$p && break\n" ..
      "done\n" ..
      "if [ -n \"$B\" ]; then\n" ..
      "  echo \"bateria: $(cat $B/capacity 2>/dev/null)% ($(cat $B/status 2>/dev/null))\"\n" ..
"else\n" ..
      "  if command -v termux-battery-status >/dev/null 2>&1; then\n" ..
      "    out=$(timeout 3 termux-battery-status 2>/dev/null)\n" ..
      "    if [ -n \"$out\" ]; then\n" ..
      "      echo \"$out\" | grep -oE '\"percentage\":[0-9.]+|\"status\":\"[^\"]+\"'\n" ..
      "    else\n" ..
      "      echo \"bateria indisponível — instale Termux:API e pkg install termux-api\"\n" ..
      "    fi\n" ..
      "  else\n" ..
      "    echo \"bateria indisponível — instale Termux:API e pkg install termux-api\"\n" ..
      "  fi\n" ..
      "fi")
end

vim.register("battery", function() M.run() end)
return M