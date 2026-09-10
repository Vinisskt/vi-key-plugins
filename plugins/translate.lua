-- translate.lua — :tr — tradução PT<->EN pelo translate-shell (online).
-- Requer o daemon ipc-loop.lua rodando no Termux e o pacote translate-shell
-- (pkg install translate-shell). Usa o Google Translate via `trans` e precisa
-- de internet; a direção vem do trans (-identify), com fallback heurístico.
-- Formas:
--   :tr <texto>    traduz o literal e devolve ao app (substitui seleção; senão
--                  insere no cursor)
--   :tr            texto da seleção, senão o texto todo (substitui tudo)
--   :tr -v [texto] só mostra (status <=300c, senão página); não toca no app
local termux = require("termux")
local sh = require("shell")

local MISSING = "TRANS_ERR_MISSING"
local MAX_CHARS = 2500 -- limite do trecho traduzido de uma vez
local ANSI = "\27%[[%d;]*m" -- sequências ANSI do trans

-- Palavras-pivô p/ fallback de direção (identify falhou ou empate).
local PT_WORDS = {
  "a", "o", "as", "os", "de", "do", "da", "dos", "das", "em", "no", "na",
  "nos", "nas", "que", "e", "um", "uma", "uns", "umas", "para", "com",
  "por", "é", "não", "se", "aos", "como", "ser", "está", "seu", "sua",
  "foi", "mais", "isso", "outro",
}
local EN_WORDS = {
  "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "of",
  "for", "with", "is", "it", "are", "was", "were", "have", "has", "not",
  "that", "this", "these", "those", "you", "what", "be", "us", "as", "if",
}

-- Comando bash que garante a presença do trans e distingue falha de ausência.
-- timeout evita travar o daemon em rede lenta (heartbeat congela durante
-- execução — parecia "daemon morreu").
local function trans_cmd(args)
  return "if command -v trans >/dev/null 2>&1; then timeout 20 trans " .. args
    .. "; else echo '" .. MISSING .. "'; fi"
end

-- Direção por contagem de palavras-pivô (pt > en => "pt", senão "en").
local function heur_src(text)
  local words = {}
  for w in text:lower():gmatch("%a+") do words[#words + 1] = w end
  local pt, en = 0, 0
  local pset, eset = {}, {}
  for _, w in ipairs(PT_WORDS) do pset[w] = true end
  for _, w in ipairs(EN_WORDS) do eset[w] = true end
  for _, w in ipairs(words) do
    if pset[w] then pt = pt + 1 end
    if eset[w] then en = en + 1 end
  end
  return (pt > en) and "pt" or "en"
end

-- Detecta o idioma-fonte via trans. Devolve "pt", "en", ou nil com motivo:
--   "net"      sem resposta/erro de rede
--   "missing"  trans não instalado
--   "detec"    idioma detectado não é pt/en (segue por heurística)
-- Como identificador: "Portugu" (pt) tem prioridade; "English" só prossegue
-- se não houver nada em português antes (a descrição pt não cita "English").
local function identify(text)
  local out = termux.exec(trans_cmd("-identify -no-ansi " .. sh.shq(text)))
  if not out or out == "" then return nil, "net" end
  if out == MISSING then return nil, "missing" end
  local first = (out:match("^[^\n]+") or ""):gsub(ANSI, ""):gsub("^%s+", "")
  if out:find("Portugu") then return "pt", "ok" end
  if out:find("English") then return "en", "ok" end
  return nil, "detec", first
end

local function do_translate(text, src)
  local dst = (src == "pt") and "en" or "pt"
  return termux.exec(trans_cmd("-b -no-ansi -s " .. src .. " -t " .. dst
    .. " " .. sh.shq(text)))
end

-- Limpa a saída do trans; devolve nil se for erro/identidade.
local function clean_trans(out, original)
  if not out or out == "" then return nil end
  if out == MISSING then return nil, "instale translate-shell" end
  local s = out:gsub(ANSI, ""):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" or s:find("[ERROR]", 1, true) then return nil end
  s = s:gsub("\n+", "\n")
  local o = original:gsub("[%s%p]+", ""):lower()
  if s:gsub("[%s%p]+", ""):lower() == o then return nil, "idêntico" end
  return s
end

vim.register("tr", function(...)
  local args = { ... }
  local visual, rest = false, {}
  for _, a in ipairs(args) do
    if a == "-v" or a == "--view" then
      visual = true
    else
      rest[#rest + 1] = tostring(a)
    end
  end

  local text, sel0, sel1
  if #rest > 0 then
    text = table.concat(rest, " ")
  else
    local all = vim.get_text()
    sel0, sel1 = vim.get_sel()
    if sel0 ~= nil and sel1 ~= nil and sel0 ~= sel1 then
      text = all:sub(sel0 + 1, sel1)
    else
      text = all
    end
  end
  text = (text or ""):gsub("[%s]+", " ")
  if text == "" then
    vim.status(":tr — texto vazio")
    return
  end

  local truncated = #text > MAX_CHARS
  local original = text
  text = text:sub(1, MAX_CHARS)

  local src, why, detected = identify(text)
  if not src then
    if why == "net" then
      vim.status(":tr — sem resposta do trans (internet?)")
    elseif why == "missing" then
      vim.status(":tr — instale o translate-shell (pkg install translate-shell)")
    else
      src = heur_src(text) -- idioma exótico/ambiguo: segue pela heurística
    end
  end
  if not src then return end

  local out = clean_trans(do_translate(text, src), text)
  if not out then
    -- Resultado improvável (idêntico/erro): tenta a direção contrária.
    local alt = (src == "pt") and "en" or "pt"
    out = clean_trans(do_translate(text, alt), text)
  end
  if not out then
    vim.status(":tr — sem tradução")
    return
  end
  if truncated then
    out = out .. "\n(porção inicial traduzida)"
  end

  if visual then
    if #out > 300 then vim.page(out) else vim.status(out) end
    return
  end

  -- Devolve ao app: troca a seleção; arg sem seleção => insere no cursor;
  -- texto completo => substitui tudo.
  if sel0 ~= nil and sel1 ~= nil and sel0 ~= sel1 then
    vim.replace(sel0, sel1, out)
  elseif #rest > 0 then
    vim.send(out)
  else
    vim.replace(0, #vim.get_text(), out)
  end

  local short = out:gsub("\n", " ")
  if #short > 80 then short = short:sub(1, 80) .. "…" end
  vim.status(":tr → " .. short)
end)

return {}