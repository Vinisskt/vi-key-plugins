-- tokyo.lua — tema Tokyo Night para o vi-key.
-- Paleta "Night" oficial (enkia/tokyo-night): fundo #1a1b26, texto lavanda
-- #c0caf5 e acentos em azul/roxo. Aplica na hora, sem reiniciar o app.
--
--   :tokyo          aplica o tema Tokyo Night
--   :tokyo off      volta ao tema padrão (gruvbox)
--   :theme [nome]   mostra o tema atual (ou troca para [nome])
local vim = vim

vim.theme("tokyo", {
  colorKeyboard         = "#1a1b26", -- Background (Night): fundo do teclado
  colorKey              = "#292e42", -- Line Highlight: teclas
  colorKeyActivated     = "#414868", -- Terminal Black: tecla pressionada
  colorKeyAction        = "#7156a8", -- roxo escuro: teclas importantes/de função
  colorKeySpaceBar      = "#24283b", -- Background (Storm)
  colorLabel            = "#c0caf5", -- Foreground: rótulo das teclas
  colorLabelPressed     = "#c0caf5",
  colorLabelActivated   = "#7aa2f7", -- Blue: mod ligado/ativo
  colorLabelLocked      = "#f7768e", -- Red: caps/num lock
  colorSubLabel         = "#565f89", -- Comment: duplo toque/acentos
  secondaryDimming      = 0.3,       -- números em float
  keyBorderRadius       = 3.0,       -- dimensões em dp
  navigationBarColor    = "#1a1b26", -- Background
  windowLightNavigationBar = false,
})

vim.register("tokyo", function(arg)
  if arg == "off" then
    vim.set_theme("")
    vim.status("tema padrão (gruvbox)")
    return
  end
  if arg and arg ~= "" then
    vim.status("tokyo: argumento '" .. arg .. "' ignorado")
    return
  end
  vim.set_theme("tokyo")
  vim.status("tema tokyo ativo")
end)

return {}