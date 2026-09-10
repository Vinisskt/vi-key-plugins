-- init.lua — ponto de entrada dos plugins, carregado pelo teclado.
-- Cada plugin é um módulo em plugins/ (nome do arquivo = comando):
--   require("termux")   -> :termux  (porta para o Termux / ferramentas Linux)
--   require("ipc-loop") -> :ipcloop (daemon da ponte, roda no Termux)
require("termux")
require("ipc-loop")

-- Utilitários (usam a ponte :termux):
require("cat")      -- :cat <caminho>          mostra um arquivo
require("files")    -- :files [caminho]        lista arquivos
require("ip")       -- :ip                     endereços de rede
require("which")    -- :which <prog...>        caminho de executáveis
require("calc")     -- :calc <expr>            calculadora (Lua)
require("battery")  -- :battery                nível/status da bateria
require("sysinfo")  -- :sysinfo [net|cpu|mem|disk]
require("todo")     -- :todo [add|del|done]    lista pessoal
require("ping")     -- :ping <host>            latência de rede
require("pkg")      -- :pkg <op> [alvos]       pacotes do Termux
require("weather")  -- :weather [cidade]       previsão do tempo
require("translate") -- :tr [texto] | :tr -v    tradução PT<->EN (translate-shell)