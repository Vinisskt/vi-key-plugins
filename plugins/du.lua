-- du.lua — :du [dir] — mostra onde o espaço do home está indo (du + fzf).
--   Lista <dir> (padrão $HOME) por tamanho, maiores primeiro; pastas aparecem
--   marcadas com "/" no fim:
--     Enter em PASTA   aprofunda (du naquela pasta)
--     Enter em ARQUIVO vê o conteúdo (:cat)
local termux = require("termux")
local sh = require("shell")
local fzf = require("fzf")
local cat = require("cat")

local M = {}

-- Pipeline "du -h -a -d 1" com sort por tamanho e marcação de pasta: saída por
-- linha "tamanho<TAB>caminho" (pasta => "/" no fim). "$p" sempre absoluto.
local function du_script(root_token)
  return {
    "du", "-h", "-a", "-d", "1", root_token, "|", "sort", "-hr", "|",
    "while read sz p; do [ -d \"$p\" ] && p=\"$p/\";",
    "printf '%s\\t%s\\n' \"$sz\" \"$p\"; done",
  }
end

local function dive(line)
  local path = line:match("^%S+\t(.+)$")
  if not path then return end
  if path:sub(-1) == "/" then
    M.run({ path:sub(1, -2) })        -- pasta: aprofunda nela
  else
    cat.view(path)                    -- arquivo: mostra conteúdo
  end
end

function M.run(args)
  local arg = (args[1] ~= nil and args[1] ~= "") and args[1] or nil
  fzf.run(du_script(arg and sh.shq(arg) or '"$HOME"'), dive)
end

vim.register("du", function(...) M.run({...}) end)
return M