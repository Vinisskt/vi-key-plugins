-- fzf.lua — API de busca/seleção de lista na statusbar (âncora, NÃO é comando).
-- O fzf apenas navega e filtra listas (diretórios no explorador, ou a saída de
-- um comando) e entrega a escolha por CALLBACK. Ele nunca roda nada sozinho:
-- quem age é o plugin que o chama (ex.: :cat escolhe um arquivo e o cat lê).
--
-- APIs:
--   fzf.open_explorer([caminho], on_pick)   explorador; Enter num ARQUIVO chama
--                                           on_pick(caminho_absoluto); em pasta
--                                           segue navegando; sem on_pick, Enter
--                                           num arquivo só fecha (nada roda).
--   fzf.run({comando...}, on_pick)          lista a saída do comando e chama
--                                           on_pick(linha_escolhida) no Enter.
--
-- Teclas durante a navegação/filtro:
--   setas ^/v      move o cursor (letras ficam livres para o filtro)
--   digitar        filtra a lista em tempo real (sem diferenciar maiúsculas)
--   space          digita espaço no filtro
--   backspace      apaga o último caractere do filtro
--   enter          (explorador) entra/Sobe | (arquivo/linha c/ callback) entrega
--   esc            limpa o filtro; esc de novo sai (sem rodar nada)
local termux = require("termux")
local sh = require("shell")

local status = vim.status_hold or vim.status
local M = {}
local MAX_ITEMS = 200
local WINDOW = 4
local TRUNC = 40

local list = {}
local all = {}
local n = 0
local cur = 0
local active = false
local explorer = false
local search_mode = false
local search_indexed = false
local search_pending = false
local search_indexing = false
local search_index = {}
local base = ""
local home_root = nil
local query = ""
local session = 0
-- Callback do modo seletor (open_explorer c/ on_pick): Enter num arquivo
-- chama pick_cb(caminho_absoluto) em vez de rodar; pasta continua navegando.
local pick_cb = nil
local on_key
local apply_filter
local enter_dir
local strip_home
local fill_index

-- Mostra [d] com a estrutura "~/..." quando esta dentro do home.
local function display(d)
  if home_root and d == home_root then return "~" end
  if home_root and d:sub(1, #home_root) == home_root then
    return "~" .. d:sub(#home_root + 1)
  end
  return d
end

-- Corta o MEIO da linha quando ela passa de TRUNC: mantém o começo (contexto
-- do diretório) e o fim (o nome do arquivo — era o que sumia com o recorte
-- antigo, que cortava a cauda).
local function clip(s)
  if #s <= TRUNC then return s end
  local head_n = 12
  return s:sub(1, head_n) .. "~" .. s:sub(-(TRUNC - 1 - head_n))
end

-- Em modo busca, cada resultado vira "~pasta/arquivo": o trecho da raiz do
-- home até a pasta fica oculto pelo "~", e a linha mostra só a pasta imediata
-- e o nome do arquivo (arquivo na raiz: só o nome).
local function search_display(rel)
  local dir, last = rel:match("^(.*/)([^/]+)$")
  if dir == nil then return rel end
  dir = dir:gsub("/+$", "")
  return "~" .. dir:match("[^/]+$") .. "/" .. last
end

-- Diretório acima de [d] ("~" e "/" sobem para "/").
local function parent(d)
  local t = d:gsub("/+$", "")
  if t == "" or t == "~" then return "/" end
  local p = t:match("(.*)/[^/]+$")
  if not p or p == "" then return "/" end
  return p
end

local function window_lines()
  local head = "fzf " .. cur .. "/" .. n
  if search_mode then
    head = head .. "  @~"
  elseif explorer then
    head = head .. "  @" .. clip(display(base))
  elseif pick_cb then
    head = head .. "  enter roda"
  end
  if query ~= "" then
    head = head .. "  '" .. query .. "'"
  end
  local lines = { head }
  local top = math.max(1, math.min(cur - 2, n - WINDOW + 1))
  for i = top, math.min(n, top + WINDOW - 1) do
    local item = list[i]
    if search_mode then item = search_display(item) end
    lines[#lines + 1] = ((i == cur) and ">" or " ") .. " " .. clip(item)
  end
  return table.concat(lines, "\n")
end

local function show()
  if search_indexing then
    -- Indice subindo em background: feedback imediato a cada tecla; o
    -- resultado chega sozinho quando o find termina.
    local head = "fzf 0/0  @~"
    if query ~= "" then head = head .. "  '" .. query .. "'" end
    status(head .. "\n~ indexando...")
    return
  end
  status(window_lines())
end

local function stop()
  active = false
  vim.key_hook(nil)
  pick_cb = nil
  -- Avanca a sessao: callbacks pendentes (index/descida) de instancias
  -- canceladas sao ignorados pelo guarda `session ~= my`.
  session = session + 1
end

local function split_lines(out)
  local t = {}
  for line in out:gmatch("[^\n]+") do
    t[#t + 1] = line
    if #t >= MAX_ITEMS then break end
  end
  return t
end

local function open_list(out, is_explorer, dir_base)
  all = split_lines(out)
  if #all == 0 and not is_explorer then
    stop()
    vim.status("fzf: sem resultado")
    return
  end
  explorer = is_explorer
  search_mode = false
  search_indexed = false
  search_pending = false
  search_indexing = false
  base = dir_base or ""
  query = ""
  active = true
  session = session + 1
  vim.key_hook(on_key)
  vim.set_mode("scroll")
  apply_filter()
end

-- Indexa o home uma unica vez por sessao: listagem completa de arquivos nao
-- ocultos, com profundidade limitada e podando diretorios gigantes comuns.
-- Os parenteses do find precisam de escape de shell por isso as barras.
local function index_cmd()
  return "find " .. sh.shq(home_root) ..
    " -maxdepth 8 \\( -name 'node_modules' -prune \\) -o \\( -type f -print \\)"
end

-- Garante o índice do home, sem travar o teclado: primeiro find de cada
-- sessão roda em background (exec_async) e fill_index() re-renderiza com o
-- query do momento quando concluir. As demais teclas filtram em memória.
local function ensure_index()
  if search_indexed then return end
  if search_pending then return end
  search_pending = true
  local my = session
  if termux.exec_async then
    termux.exec_async(index_cmd(), function(out)
      if session == my and active then
        fill_index(out)
        apply_filter()
      end
    end)
  else
    -- Sem exec_async (teclado antigo): preenche aqui e o chamador segue — o
    -- apply_filter de cima continua e renderiza a lista no fim.
    search_pending = false
    search_indexed = true
    search_index = {}
    local out = termux.exec(index_cmd())
    if out ~= nil then
      for line in out:gmatch("[^\n]+") do
        local rel = strip_home(line)
        if rel ~= nil and #search_index < MAX_ITEMS * 100 then
          search_index[#search_index + 1] = rel
        end
      end
    end
  end
end

-- Caminho relativo ao home ("storage/calc.txt"), ou nil se fora dele.
function strip_home(path)
  local prefix = home_root .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return nil
end

-- Preenche o indice do home quando a chamada assincrona volta e re-renderiza
-- com o query atual. So roda via ensure_index (que ja garante que a sessao nao
-- avancou e que o fzf segue ativo).
-- Preenche o indice do home quando a chamada assincrona volta. Nao renderiza:
-- quem renderiza e o chamador (o closure de ensure_index chama apply_filter
-- logo apos; quando o callback roda dentro de um apply_filter — caso dos testes
-- com mock síncrono — o proprio apply_filter da continuidade).
function fill_index(out)
  search_pending = false
  search_indexed = true
  search_index = {}
  if out ~= nil then
    for line in out:gmatch("[^\n]+") do
      local rel = strip_home(line)
      if rel ~= nil and #search_index < MAX_ITEMS * 100 then
        search_index[#search_index + 1] = rel
      end
    end
  end
end

-- Recalcula a lista a partir do filtro [query] (case-insensitive) sobre [all].
-- Filtro vazio = lista do diretório atual (".." fixo no topo); filtro ativo =
-- busca no home inteiro via find (arquivos, caminhos relativos ao home).
function apply_filter()
  local q = query:lower()
  list = {}
  search_indexing = false
  if explorer and q ~= "" then
    search_mode = true
    ensure_index()
    if not search_indexed then
      search_indexing = true
      n = 0
      cur = 0
    else
      -- Re-inicia a lista: o ensure_index acima pode ter reentrado em
      -- apply_filter (callback síncrono em testes), que já encheu [list].
      list = {}
      for _, rel in ipairs(search_index) do
        if rel:lower():find(q, 1, true) then
          list[#list + 1] = rel
          if #list >= MAX_ITEMS then break end
        end
      end
      n = #list
      cur = 1
    end
  else
    search_mode = false
    for _, item in ipairs(all) do
      if q == "" or item:lower():find(q, 1, true) then
        list[#list + 1] = item
        if #list >= MAX_ITEMS then break end
      end
    end
    if explorer then table.insert(list, 1, "..") end
    n = #list
    cur = (explorer and n >= 2) and 2 or 1
  end
  if cur > n then cur = n end
  show()
end

local function append_char(c)
  query = query .. c
  apply_filter()
end

local function pop_char()
  if query ~= "" then
    query = query:sub(1, -2)
    apply_filter()
  end
end

local function run_selected()
  local item = list[cur]
  if item == nil then return end
  local cb = pick_cb  -- stop() zera o pick_cb: guarda ANTES de sair
  local path
  if search_mode then
    path = home_root .. "/" .. item
    stop()
    vim.set_mode("insert")
  elseif explorer then
    if item == ".." then
      enter_dir(parent(base))
      return
    elseif item:sub(-1) == "/" then
      enter_dir(base:gsub("/+$", "") .. "/" .. item)
      return
    else
      -- Arquivo: CAMINHO ABSOLUTO (base + "/" + item). Antes rodava só o
      -- nome, relativo ao $HOME — não achava arquivo fora da raiz.
      path = base:gsub("/+$", "") .. "/" .. item
      stop()
      vim.set_mode("insert")
    end
  else
    path = item
    stop()
    vim.set_mode("insert")
  end
  -- Entrega a escolha SÓ por callback. Sem on_pick, Enter fecha a lista e
  -- volta pro insert: o fzf é uma âncora e nunca executa nada por conta.
  if cb then
    cb(path)
  end
end

function enter_dir(d)
  -- Descida assincrona (não trava o teclado): mostra "carregando..." na hora
  -- e a lista chega quando o ls volta. Fallback síncrono sem exec_async.
  if vim.status_hold then status("fzf: carregando...") end
  local my = session
  local finish = function(out)
    if session ~= my then return end
    if out == nil then
      vim.status("fzf: sem acesso a " .. d)
      return
    end
    open_list(out, true, d)
  end
  local cmd = "ls -A -p " .. sh.shq(d)
  if termux.exec_async then
    termux.exec_async(cmd, finish)
  else
    finish(termux.exec(cmd))
  end
end

function on_key(key)
  if not active then
    vim.key_hook(nil)
    return false
  end
  if key == "enter" then
    run_selected()
    return true
  elseif key == "esc" then
    if query ~= "" then
      query = ""
      apply_filter()
      return true
    end
    stop()
    vim.set_mode("insert")
    vim.status("fzf: cancelado")
    return true
  elseif key == "back" or key == "backspace" then
    pop_char()
    return true
  elseif key == "up" then
    if cur > 1 then cur = cur - 1; show() end
    return true
  elseif key == "down" then
    if cur < n then cur = cur + 1; show() end
    return true
  elseif key == "space" then
    append_char(" ")
    return true
  elseif #key == 1 then
    append_char(key)
    return true
  end
  return false
end

-- Abre o explorador na raiz do home (resolucao + listagem no 1o uso).
local function start_home()
  if home_root == nil then
    -- Resolucao + listagem da raiz num unico exec (1 round-trip IPC).
    -- $HOME em aspas duplas expande no bash (o shq() aspalha tudo e veda ~).
    if vim.status_hold then status("fzf: carregando...") end
    local out = termux.exec("printf '%s\\n' \"$HOME\"; ls -A -p \"$HOME\"")
    if out == nil or out == "" then
      vim.status("fzf: nao conseguiu resolver $HOME")
      return
    end
    local home = out:match("([^\n]+)")
    if not home or home == "" then
      vim.status("fzf: nao conseguiu resolver $HOME")
      return
    end
    home_root = home
    open_list(out:sub(#home + 1), true, home_root)
    return
  end
  enter_dir(home_root)  -- home cacheado: so executa a listagem
end

function M.run(args, on_pick)
  if not vim.key_hook then
    vim.status("fzf: requer atualização do teclado (vim.key_hook)")
    return
  end
  pick_cb = on_pick or nil
  if #args == 0 then
    start_home()
    return
  end
  -- Lista a saída do comando SEM travar o teclado (exec_async; quando a API
  -- não existe, o sync cai no exec de sempre).
  local my = session
  local cmd = table.concat(args, " ")
  local finish = function(out)
    if session ~= my then return end
    if out == nil or out == "" then
      vim.status("fzf: sem resultado (comando >6s ou nada na saída)")
      return
    end
    open_list(out, false, nil)
  end
  if termux.exec_async then
    termux.exec_async(cmd, finish)
  else
    finish(termux.exec(cmd))
  end
end

-- API para outros plugins (fzf é âncora: nunca roda nada, só entrega por callback):
--   fzf.open_explorer()                     explorador na raiz do home
--   fzf.open_explorer(caminho[, on_pick])   explorador enraizado em [caminho];
--                                           Enter num ARQUIVO chama on_pick(caminho
--                                           absoluto), em pasta segue navegando;
--                                           sem callback, arquivo só fecha.
--   fzf.run({comando...}[, on_pick])        lista a saída do comando e chama
--                                           on_pick(linha) no Enter.
function M.open_explorer(start, on_pick)
  if not vim.key_hook then
    vim.status("fzf: requer atualização do teclado (vim.key_hook)")
    return
  end
  pick_cb = on_pick or nil
  if start == nil or start == "" then
    start_home()
  else
    enter_dir(start)
  end
end

-- Sem comando registrado: o fzf entra só via API (require("fzf")) pelas âncoras.
return M