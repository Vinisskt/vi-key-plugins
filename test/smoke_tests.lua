-- smoke_tests.lua — carrega TODOS os plugins do init.lua num ambiente isolado
-- e confere que nenhum quebra no load e que os comandos esperados existem.
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local ALL = {
  ["termux"]    = { "termux", "$" },
  ["ipc-loop"]  = { "ipcloop" },
  ["cat"]       = { "cat" },
  ["rg"]        = { "rg" },
  ["hist"]      = { "hist" },
  ["du"]        = { "du" },
  ["man"]       = { "man" },
  ["snip"]      = { "snip" },
  ["ps"]        = { "ps" },
  ["ip"]        = { "ip" },
  ["which"]     = { "which" },
  ["calc"]      = { "calc" },
  ["battery"]   = { "battery" },
  ["sysinfo"]   = { "sysinfo" },
  ["todo"]      = { "todo" },
  ["ping"]      = { "ping" },
  ["pkg"]       = { "pkg" },
  ["weather"]   = { "weather" },
  ["translate"] = { "tr" },
  ["scroll"]    = { "scroll" },
  ["gruvbox"]   = { "gruvbox", "theme" },
  ["dracula"]   = { "dracula" },
  ["tokyo"]     = { "tokyo" },
}

local count = 0
local missing = {}
for name, cmds in pairs(ALL) do
  local t = sandbox.load(name, { deps = sandbox.default_deps() })
  local regs = {}
  for _, r in ipairs(t.vim.registrations) do regs[#regs + 1] = r.n end
  for _, c in ipairs(cmds) do
    local found = false
    for _, r in ipairs(regs) do if r == c then found = true end end
    if not found then
      missing[#missing + 1] = name .. " / " .. c
    else
      count = count + 1
    end
  end
end
T.section("plugins carregam e registram os comandos")
T.is("todos os comandos presentes (" .. count .. ")", #missing == 0,
  #missing > 0 and "  faltando: " .. table.concat(missing, ", ") or "")

-- fzf virou âncora: carrega (via API) mas NÃO registra comando algum.
T.section("fzf é API pura (âncora, sem comando)")
local fzft = sandbox.load("fzf", { deps = sandbox.default_deps() })
T.is("nenhum comando registrado", #fzft.vim.registrations == 0, "  registros: " .. #fzft.vim.registrations)
T.is("expõe open_explorer e run", type(fzft.ret.open_explorer) == "function" and type(fzft.ret.run) == "function")

T.done("smoke")