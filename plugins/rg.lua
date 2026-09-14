-- rg.lua — :rg <padrão> [dir] — busca de conteúdo no home com o ripgrep e
-- escolha do resultado no fzf (âncora).
--   Enter num resultado -> mostra a linha do match (sed -n '<linha>p' '<arquivo>').
--   Sem [dir], procura no home inteiro ("$HOME" expande no bash); smart-case do
--   rg: busca é case-sensitive só se o padrão tiver maiúscula.
local termux = require("termux")
local sh = require("shell")
local fzf = require("fzf")

local M = {}

local function pick_match(line)
  -- Saída do rg: "caminho:linha:conteudo" (--no-heading, -n).
  local path, lineno = line:match("^([^:]+):(%d+):")
  if not path then return end
  termux.run({ "sed -n '" .. lineno .. "p' " .. sh.shq(path) })
end

function M.run(args)
  local pattern = args[1]
  if pattern == nil or pattern == "" then
    vim.status("uso: :rg <padrão> [dir]  (dir opcional; padrão = home)")
    return
  end
  -- Padrão e dir quoteados separadamente (sh.shq); "$HOME" em aspas duplas
  -- expande no bash — por isso sai sem aspas simples (senão viraria literal).
  local list = { "rg", "-n", "--no-heading", "-S", sh.shq(pattern) }
  if args[2] ~= nil and args[2] ~= "" then
    list[#list + 1] = sh.shq(args[2])
  else
    list[#list + 1] = '"$HOME"'
  end
  fzf.run(list, pick_match)
end

vim.register("rg", function(...) M.run({...}) end)
return M