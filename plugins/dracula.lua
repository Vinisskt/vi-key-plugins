-- dracula.lua — tema Dracula (cores da paleta oficial) para o vi-key.
-- Usa a API vim.theme/vim.set_theme: registra o tema quando carregado e
-- aplica/volta ao padrão na hora, sem precisar reiniciar o app.
--
--   :dracula         aplica o tema Dracula
--   :dracula off     volta ao tema padrão (gruvbox)
--   :theme [nome]    mostra o tema atual (ou troca para [nome])
--
-- Exemplo de override parcial: apague/renomeie linhas abaixo para ver o
-- teclado usar o valor padrão (gruvbox) nos atributos omitidos.
local vim = vim

vim.theme("dracula", {
  -- Cores oficiais do Dracula (spec.draculatheme.com): Background #282a36,
  -- Current Line/Selection #44475a, Foreground #f8f8f2, Comment #6272a4,
  -- Green #50fa7b (funções), Red #ff5555 (deleção). As teclas importantes
  -- usam um roxo escuro (#7156a8) derivado do Pink oficial #ff79c6.
  colorKeyboard         = "#282a36", -- Background: fundo do teclado (sólido)
  colorKey              = "#44475a", -- Selection: teclas normais
  colorKeyActivated     = "#6272a4", -- Comment: tecla pressionada
  colorKeyAction        = "#7156a8", -- roxo escuro: teclas importantes/de função
  colorKeySpaceBar      = "#44475a",
  colorLabel            = "#f8f8f2", -- Foreground: rótulo das teclas
  colorLabelPressed     = "#f8f8f2",
  colorLabelActivated   = "#50fa7b", -- Green: mod ligado/ativo
  colorLabelLocked      = "#ff5555", -- Red: caps/num lock
  colorSubLabel         = "#6272a4", -- Comment: duplo toque/acentos
  secondaryDimming      = 0.3,       -- números em float
  keyBorderRadius       = 3.0,       -- dimensões em dp
  navigationBarColor    = "#282a36", -- Background
  windowLightNavigationBar = false,
})

vim.register("dracula", function(arg)
  if arg == "off" then
    vim.set_theme("")
    vim.status("tema padrão (gruvbox)")
    return
  end
  if arg and arg ~= "" then
    vim.status("dracula: argumento '" .. arg .. "' ignorado")
    return
  end
  vim.set_theme("dracula")
  vim.status("tema dracula ativo")
end)

vim.register("theme", function(arg)
  if not arg or arg == "" then
    vim.status("tema atual: " .. vim.current_theme())
    return
  end
  if arg == "default" or arg == "gruvbox" then
    vim.set_theme("")
    vim.status("tema padrão (gruvbox)")
  else
    vim.set_theme(arg)
  end
end)

return {}