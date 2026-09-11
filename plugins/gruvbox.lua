-- gruvbox.lua — tema Gruvbox para o vi-key.
-- Igual ao padrão embutido do teclado (estilo Gruvbox em res/values/themes.xml);
-- registra o tema para você poder voltar ao visual original quando quiser.
--
--   :gruvbox        volta ao tema padrão (gruvbox embutido)
--   :theme [nome]   mostra o tema atual (ou troca para [nome])
local vim = vim

-- A API trata "gruvbox" como sinônimo do tema embutido: aplicar este tema
-- sempre usa o padrão do app. A paleta fica registrada aqui apenas como
-- referência/editação das cores (equivalente 1:1 ao estilo embutido).
vim.theme("gruvbox", {
  colorKeyboard         = "#1d2021", -- fundo do teclado (um pouco mais escuro que as teclas)
  colorKey              = "#282828", -- teclas
  colorKeyActivated     = "#4d4845", -- tecla pressionada
  colorKeyAction        = "#3c3836", -- teclas de função
  colorKeySpaceBar      = "#2e2b29",
  colorLabel            = "#ebdbb2", -- rótulo das teclas
  colorLabelPressed     = "#fabd2f", -- ao apertar
  colorLabelActivated   = "#83a598", -- mod ligado/ativo
  colorLabelLocked      = "#8ec07c", -- caps/num lock
  colorSubLabel         = "#d5c4a1", -- duplo toque/acentos
  secondaryDimming      = 0.25,
  keyBorderRadius       = 6.0,       -- dimensões em dp
  keyBorderWidth        = 0.8,
  keyBorderColorLeft    = "#30302f",
  keyBorderColorTop     = "#3c3836",
  keyBorderColorRight   = "#30302f",
  keyBorderColorBottom  = "#0f0f10",
  navigationBarColor    = "#1d2021",
  windowLightNavigationBar = false,
})

vim.register("gruvbox", function(arg)
  if arg and arg ~= "" and arg ~= "off" then
    vim.status("gruvbox: argumento '" .. arg .. "' ignorado")
    return
  end
  vim.set_theme("gruvbox")
  vim.status("tema padrão (gruvbox)")
end)

return {}