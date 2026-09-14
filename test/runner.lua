-- runner.lua — mini framework compartilhado pelas suítes de testes.
-- Cada arquivo *_tests.lua faz  local T = dofile("test/runner.lua")  alí em cima
-- e termina com  T.done("<rótulo>")  (os.exit 0/1). A contagem é por processo,
-- então run.sh roda um arquivo por invocação de lua5.1.
local T = {}

T.pass, T.fail = 0, 0
local failures = {}

local function head(s)
  return (s .. ""):gsub("\n.*", "")
end

function T.section(title)
  print("\n== " .. title .. " ==")
end

function T.ok(name, cond)
  if cond then
    T.pass = T.pass + 1
  else
    T.fail = T.fail + 1
    failures[#failures + 1] = name
    print("  FALHOU: " .. name)
  end
end

function T.eq(name, a, b)
  T.ok(name .. " <" .. head(tostring(a)) .. "> == <" .. head(tostring(b)) .. ">", a == b)
end

function T.is(name, cond, msg)
  T.ok(name .. (msg or ""), cond)
end

-- Igualdade profunda de arrays (para comparar listas/registros).
function T.seqeq(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    if not T.seqeq(a[i], b[i]) then return false end
  end
  return true
end

-- Mesmo quoting do plugin shell.shq (p/ montar expected em testes).
function T.shq(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function T.contains(name, needle, haystack)
  T.ok(name .. " (a procura de <" .. head(needle) .. ">)", (haystack .. ""):find(needle, 1, true) ~= nil)
end

function T.notcontains(name, needle, haystack)
  T.ok(name .. " (<" .. head(needle) .. "> não deve estar)", (haystack .. ""):find(needle, 1, true) == nil)
end

function T.done(tag)
  print(("----------------------------------------\n%s: Passou: %d   Falhou: %d"):format(tag or "total", T.pass, T.fail))
  if T.fail > 0 then
    for _, n in ipairs(failures) do print("  - " .. n) end
  end
  os.exit(T.fail > 0 and 1 or 0)
end

return T