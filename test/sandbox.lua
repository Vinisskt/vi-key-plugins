-- sandbox.lua — ambiente vi-key isolado para carregar plugins/*.lua em testes.
-- Uso:
--   local sandbox = dofile("test/sandbox.lua")
--   local t = sandbox.load("translate", { deps = { termux = {...} } })
--   t.vim.registrations  t.vim.statuses  t.vim.holds  t.vim.modes ...
--   t.deps.termux.calls  (mock padrão com captura)  t.ret
-- O mock padrão de require devolve deps.termux / deps.shell / deps.fzf; o resto
-- cai no _G real (string/table/os/io), então os testes podem usar arquivos de
-- verdade numa data/ temporária quando precisarem.
--
-- ATENÇÃO Lua 5.1: `local x = { f = function() x ... end }` resolve o `x` como
-- GLOBAL (footgun do escopo do construtor). Por isso tudo aqui declara o local
-- antes (`local x` + `x = {}` + preenche), igual ao harness original do fzf.
local sandbox = {}

-- Mock padrão de vim. Todos os métodos gravam chamadas em tabelas inspecionáveis.
-- Monilha: o.get_text/get_sel permitem simular o texto/seleção do app.
function sandbox.vim_prelude(o)
  local vim = {}
  vim.registrations = {}
  vim.statuses = {}
  vim.holds = {}
  vim.modes = {}
  vim.hooks = {}
  vim.intervals = {}
  vim.repls = {}
  vim.sends = {}
  vim.pages = {}
  vim.palettes = {}
  vim.seth = {}
  vim.current = "gruvbox"
  vim.n_cleared = 0
  vim.register = function(n, f) vim.registrations[#vim.registrations + 1] = { n = n, f = f } end
  vim.status = function(s) vim.statuses[#vim.statuses + 1] = s end
  vim.status_hold = function(s) vim.holds[#vim.holds + 1] = s end
  vim.set_mode = function(m) vim.modes[#vim.modes + 1] = m end
  vim.key_hook = function(f) vim.hooks[#vim.hooks + 1] = f end
  vim.clear_interval = function() vim.n_cleared = vim.n_cleared + 1 end
  if not o.no_interval then
    vim.interval = function(ms, cb)
      local h = { ms = ms, cb = cb }
      vim.intervals[#vim.intervals + 1] = h
      return h
    end
  end
  vim.theme = function(n, pal) vim.palettes[n] = pal end
  vim.set_theme = function(n) vim.current = n; vim.seth[#vim.seth + 1] = n end
  vim.current_theme = function() return vim.current end
  if o.get_text then
    vim.get_text = function() return o.get_text() end
  else
    vim.get_text = function() return "" end
  end
  if o.get_sel then
    vim.get_sel = function() return o.get_sel() end
  else
    vim.get_sel = function() return nil, nil end
  end
  vim.replace = function(a, b, s) vim.repls[#vim.repls + 1] = { a, b, s } end
  vim.send = function(s) vim.sends[#vim.sends + 1] = s end
  vim.page = function(s) vim.pages[#vim.pages + 1] = s end
  return vim
end

-- Mocks padrão dos módulos requeridos pelos plugins.
function sandbox.default_deps()
  local termux = {}
  termux.calls = {}
  termux.exec = function() return "" end
  termux.exec_async = nil
  termux.run = function(scripts)
    if type(scripts) ~= "table" then scripts = { scripts } end
    for _, s in ipairs(scripts) do termux.calls[#termux.calls + 1] = s end
  end
  local shell = {}
  shell.shq = function(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\\''") .. "'"
  end
  local fzf = {}
  fzf.open_explorer = function() end
  fzf.run = function() end
  local cat = {}
  -- Espelha o cat real: view(caminho) -> termux.run({ "cat <shq>" }).
  cat.view = function(path)
    termux.run({ "cat " .. shell.shq(path) })
  end
  return { termux = termux, shell = shell, fzf = fzf, cat = cat }
end

-- Carrega plugins/<name>.lua num ambiente novo. Retorna { vim, deps, ret, env }.
function sandbox.load(name, o)
  o = o or {}
  local vim = sandbox.vim_prelude(o)
  local deps = o.deps or sandbox.default_deps()
  local env = {
    vim = vim,
    require = function(mod)
      local m = deps[mod]
      if m then return m end
      error("modulo nao registrado no sandbox: " .. tostring(mod))
    end,
  }
  setmetatable(env, { __index = _G })
  env._G = env
  local path = "plugins/" .. name .. ".lua"
  local chunk, err = loadfile(path)
  if not chunk then error("loadfile " .. path .. ": " .. tostring(err)) end
  setfenv(chunk, env)
  local ok, ret = pcall(chunk)
  if not ok then error("execucao de " .. path .. " falhou: " .. tostring(ret)) end
  return { name = name, vim = vim, deps = deps, ret = ret, env = env }
end

-- Acha o comando [n] registrado e devolve a função (ou nil).
function sandbox.command(t, n)
  for _, r in ipairs(t.vim.registrations) do
    if r.n == n then return r.f end
  end
  return nil
end

return sandbox