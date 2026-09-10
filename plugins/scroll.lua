-- scroll.lua — :scroll — entra no modo scroll.
-- Nesse modo, j/k enviam setas (DPAD) que rolam listas/grades no app
-- (WhatsApp, Twitter, etc). ESC ou i voltam ao modo insert.
-- Exemplo: `:scroll` → j/k rolam → ESC → volta a digitar.
vim.register("scroll", function(...)
  vim.set_mode("scroll")
end)
return {}