-- init.lua — ponto de entrada dos plugins, carregado pelo teclado.
--
-- A tabela [plugins] organiza os plugins por categoria; cada categoria é
-- uma lista de nomes de módulos em plugins/<nome>.lua. Para desativar um
-- plugin basta comentar a linha dele (ele não é carregado e nenhum comando
-- dele fica disponível). Nos temas, deixe descomentados só os que quiser
-- usar (ex.: 2 ou 3) e alterne com :theme <nome>.

local plugins = {

  -- ===== Núcleo (recomendado manter) =====
  nucleo = {
    "termux",      -- :termux   porta para o Termux / ferramentas Linux
    "ipc-loop",    -- :ipcloop  daemon da ponte (roda no Termux)
  },

  -- ===== Utilitários (usam a ponte :termux) =====
  utilitarios = {
    "fzf",         -- fzf (âncora, sem comando): busca/seleção via API p/ :cat e demais
    "cat",         -- :cat <caminho> ou só :cat (escolhe no explorador do fzf)
    "rg",          -- :rg <padrão> [dir]      busca no home (Enter = linha do match)
    "hist",        -- :hist                    re-executa comando do histórico (Ctrl-R)
    "du",          -- :du [dir]                espaço por pasta/arquivo (Enter aprofunda)
    "man",         -- :man <cmd> [seção]        página de manual do Linux
    "snip",        -- :snip                      cola snippet de ~/.snippets no cursor
    "ps",          -- :ps                        lista processos (Enter = kill <pid>)
    "ip",          -- :ip                     endereços de rede
    "which",       -- :which <prog...>        caminho de executáveis
    "calc",        -- :calc <expr>            calculadora (Lua)
    "battery",     -- :battery                nível/status da bateria
    "sysinfo",     -- :sysinfo [net|cpu|mem|disk]
    "todo",        -- :todo [add|del|done]    lista pessoal
    "ping",        -- :ping <host>            latência de rede
    "pkg",         -- :pkg <op> [alvos]       pacotes do Termux
    "weather",     -- :weather [cidade]       previsão do tempo
    "translate",   -- :tr [texto] | :tr -v    tradução PT<->EN (translate-shell)
    "scroll",      -- :scroll                  modo scroll (j/k rolam listas)
    "dicionario",  -- :dict                    autocorreção PT nativa offline (watcher)
  },

  -- ===== Temas (deixe descomentados só os que quiser alternar) =====
  temas = {
    "gruvbox",     -- :gruvbox / :theme gruvbox  volta ao padrão embutido do app
    "dracula",     -- :dracula / :theme dracula  tema Dracula (paleta oficial)
    "tokyo",       -- :tokyo / :theme tokyo      tema Tokyo Night (paleta oficial)
    -- "monokai",  -- (exemplo: tema extra, :theme monokai)
  },
}

-- Ordem de carregamento: categorias abaixo, na mesma ordem da tabela e
-- dentro de cada categoria, os plugins na ordem da lista.
local categories = { "nucleo", "utilitarios", "temas" }
for _, cat in ipairs(categories) do
  for _, name in ipairs(plugins[cat]) do
    local ok, err = pcall(require, name)
    if not ok then
      vim.status("plugin '" .. name .. "' falhou: " .. err)
    end
  end
end

return {}