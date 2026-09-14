-- themes_tests.lua — cobertura dos plugins de tema (gruvbox/dracula/tokyo).
-- Valida: paleta registrada, comando próprio, :theme único (gruvbox), off,
-- argumento estranho ignorado, e ausência de registro duplicado do :theme.
local T = dofile("test/runner.lua")
local sandbox = dofile("test/sandbox.lua")

local function cmds(t)
  local c = {}
  for _, r in ipairs(t.vim.registrations) do c[#c + 1] = r.n end
  return c
end

T.section("A. gruvbox — paleta e comando")
local g = sandbox.load("gruvbox", { deps = sandbox.default_deps() })
T.is("paleta registrada", g.vim.palettes.gruvbox ~= nil)
T.eq("fundo do teclado", g.vim.palettes.gruvbox.colorKeyboard, "#1d2021")
T.eq("rótulo", g.vim.palettes.gruvbox.colorLabel, "#ebdbb2")
T.eq("gedge", g.vim.palettes.gruvbox.keyBorderRadius, 6.0)

T.section("B. gruvbox — :gruvbox")
local gru = sandbox.command(g, "gruvbox")
T.is(":gruvbox registrado", gru ~= nil)
gru(nil)
T.eq("aplica gruvbox (builtin)", g.vim.seth[#g.vim.seth], "gruvbox")
T.eq("status", g.vim.statuses[#g.vim.statuses], "tema padrão (gruvbox)")
gru("off")
T.eq(":gruvbox off também aplica", g.vim.seth[#g.vim.seth], "gruvbox")
gru("xyz")
T.is("argumento estranho ignorado", g.vim.statuses[#g.vim.statuses]:find("ignorado") ~= nil)
T.eq("ignorado não aplica nada", #g.vim.seth, 2)

T.section("C. :theme registrado UMA única vez, no gruvbox")
T.is("gruvbox tem :theme", sandbox.command(g, "theme") ~= nil)
local found_themes = 0
for _, n in ipairs(cmds(g)) do if n == "theme" then found_themes = found_themes + 1 end end
T.eq(":theme aparece 1x no gruvbox", found_themes, 1)

T.section("D. dracula — paleta, comando; SEM :theme")
local d = sandbox.load("dracula", { deps = sandbox.default_deps() })
T.is("paleta dracula", d.vim.palettes.dracula ~= nil)
T.eq("fundo", d.vim.palettes.dracula.colorKeyboard, "#282a36")
T.eq("verde (ativado)", d.vim.palettes.dracula.colorLabelActivated, "#50fa7b")
T.eq("vermelho (lock)", d.vim.palettes.dracula.colorLabelLocked, "#ff5555")
T.is(":dracula registrado", sandbox.command(d, "dracula") ~= nil)
T.is("dracula NÃO registra :theme (centralizado no gruvbox)", sandbox.command(d, "theme") == nil)

local dra = sandbox.command(d, "dracula")
dra(nil)
T.eq("aplica dracula", d.vim.seth[#d.vim.seth], "dracula")
T.eq("status ativo", d.vim.statuses[#d.vim.statuses], "tema dracula ativo")
dra("off")
T.eq("off volta ao padrão ('')", d.vim.seth[#d.vim.seth], "")
dra("zzz")
T.is("arg estranho ignorado", d.vim.statuses[#d.vim.statuses]:find("ignorado") ~= nil)

T.section("E. tokyo — paleta, comando; SEM :theme")
local y = sandbox.load("tokyo", { deps = sandbox.default_deps() })
T.is("paleta tokyo", y.vim.palettes.tokyo ~= nil)
T.eq("fundo", y.vim.palettes.tokyo.colorKeyboard, "#1a1b26")
T.eq("azul (ativado)", y.vim.palettes.tokyo.colorLabelActivated, "#7aa2f7")
T.is(":tokyo registrado", sandbox.command(y, "tokyo") ~= nil)
T.is("tokyo NÃO registra :theme", sandbox.command(y, "theme") == nil)

local tok = sandbox.command(y, "tokyo")
tok(nil)
y.current = "tokyo"
T.eq("aplica tokyo", y.vim.seth[#y.vim.seth], "tokyo")
tok("off")
T.eq("off volta ao padrão", y.vim.seth[#y.vim.seth], "")

T.section("F. :theme — mostra/alterna/restaura")
local th = sandbox.command(g, "theme")
g.vim.current = "dracula"
th(nil)
T.eq("mostra atual", g.vim.statuses[#g.vim.statuses], "tema atual: dracula")
th("tokyo")
T.eq("troca para outro tema", g.vim.seth[#g.vim.seth], "tokyo")
th("gruvbox")
T.eq(":theme gruvbox volta ao padrão", g.vim.seth[#g.vim.seth], "")
th("default")
T.eq(":theme default volta ao padrão", g.vim.seth[#g.vim.seth], "")
th("off")
T.eq(":theme off volta ao padrão", g.vim.seth[#g.vim.seth], "")
th(nil)
T.eq("após off, :theme mostra padrão embutido", g.vim.statuses[#g.vim.statuses], "tema atual: ")

T.done("themes")