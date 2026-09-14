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

-- Pivôs acentuados: `%a` no locale C só casa ASCII — "é"/"não"/"está" nunca
-- contariam na varredura por palavra. Detecta por substring pura no texto cru.
local PT_RAW = { "é", "não", "está", "só" }
-- Direção por contagem de palavras-pivô (pt > en => "pt", senão "en").
local function heur_src(text)
  text = text or ""
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
  for _, w in ipairs(PT_RAW) do
    if text:find(w, 1, true) then pt = pt + 1 end
  end
  return (pt > en) and "pt" or "en"
end

-- Detecta o idioma-fonte a partir da SAÍDA do trans (parte pura, testável).
-- Devolve "pt", "en", ou nil com motivo:
--   "net"      sem resposta/erro de rede
--   "missing"  trans não instalado
--   "detec"    idioma detectado não é pt/en (segue por heurística)
-- Como identificador: "Portugu" (pt) tem prioridade; "English" só prossegue
-- se não houver nada em português antes (a descrição pt não cita "English").
local function identify_out(out)
  if not out or out == "" then return nil, "net" end
  if out == MISSING then return nil, "missing" end
  local first = (out:match("^[^\n]+") or ""):gsub(ANSI, ""):gsub("^%s+", "")
  if out:find("Portugu") then return "pt", "ok" end
  if out:find("English") then return "en", "ok" end
  return nil, "detec", first
end

-- Roda o trans -identify e entrega via ondone(src, why, detected). Prefere
-- exec_async (o teclado nunca fica preso na espera síncrona); sem a API, cai
-- para o exec de sempre.
local function identify(text, ondone)
  local cmd = trans_cmd("-identify -no-ansi " .. sh.shq(text))
  if termux.exec_async then
    termux.exec_async(cmd, function(out) ondone(identify_out(out)) end)
  else
    ondone(identify_out(termux.exec(cmd)))
  end
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

-- Traduz [text] para o oposto de [src] já limpo: ondone(out); out = nil se
-- o trans falhou ou devolveu o próprio original.
local function do_translate(text, src, ondone)
  local dst = (src == "pt") and "en" or "pt"
  local cmd = trans_cmd("-b -no-ansi -s " .. src .. " -t " .. dst
    .. " " .. sh.shq(text))
  if termux.exec_async then
    termux.exec_async(cmd, function(out) ondone(clean_trans(out, text)) end)
  else
    ondone(clean_trans(termux.exec(cmd), text))
  end
end

-- Tenta [src] e, se o resultado for improvável (erro/idêntico), a direção
-- contrária. Entrega o texto final via ondone(out).
local function translate_for_real(text, src, ondone)
  do_translate(text, src, function(out)
    if out then ondone(out); return end
    do_translate(text, (src == "pt") and "en" or "pt", ondone)
  end)
end

-- Aplica o resultado no app (substitui seleção / insere no cursor / troca
-- tudo), mostra só (page/status), e lança o status de confirmação.
local function finish(out, truncated, visual, sel0, sel1, has_args)
  if not out then
    vim.status(":tr — sem tradução")
    return
  end
  if truncated then out = out .. "\n(porção inicial traduzida)" end
  if visual then
    if #out > 300 then vim.page(out) else vim.status(out) end
    return
  end
  if sel0 ~= nil and sel1 ~= nil and sel0 ~= sel1 then
    vim.replace(sel0, sel1, out)
  elseif has_args then
    vim.send(out)
  else
    vim.replace(0, #vim.get_text(), out)
  end
  local short = out:gsub("\n", " ")
  if #short > 80 then short = short:sub(1, 80) .. "…" end
  vim.status(":tr → " .. short)
end

vim.register("tr", function(...)
  local visual, rest = false, {}
  for _, a in ipairs({ ... }) do
    if a == "-v" or a == "--view" then
      visual = true
    else
      rest[#rest + 1] = tostring(a)
    end
  end

  local text, sel0, sel1
  local has_args = #rest > 0
  if has_args then
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
  -- Colapsa espaços múltiplos e tira as pontas: "   "/`" a  b "` viram ""/"a b".
  text = (text or ""):gsub("[%s]+", " "):match("^%s*(.-)%s*$") or ""
  if text == "" then
    vim.status(":tr — texto vazio")
    return
  end

  local truncated = #text > MAX_CHARS
  text = text:sub(1, MAX_CHARS)

  identify(text, function(src, why)
    if not src then
      if why == "net" then
        vim.status(":tr — sem resposta do trans (internet?)")
        return
      elseif why == "missing" then
        vim.status(":tr — instale o translate-shell (pkg install translate-shell)")
        return
      end
      src = heur_src(text) -- idioma exótico/ambíguo: segue pela heurística
    end
    if not src then return end
    translate_for_real(text, src, function(out)
      finish(out, truncated, visual, sel0, sel1, has_args)
    end)
  end)
end)

return {
  trans_cmd   = trans_cmd,   -- monta o comando bash garantindo o trans
  heur_src    = heur_src,    -- direção heurística por palavras-pivô
  clean_trans = clean_trans, -- limpa/valida a saída do trans
  identify_out = identify_out, -- direção vinda da saída do -identify
}