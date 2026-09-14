#!/bin/sh
# Roda toda a suíte de testes dos plugins. Requer lua5.1 (mesmo runtime do
# teclado). Cada *_tests.lua é um processo (os.exit 0/1) e o script aborta na
# primeira falha. Ex.: ./test/run.sh  (ou: test/run.sh <suíte>)
cd "$(dirname "$0")/.." || exit 1

run() {
  printf '>>> %s\n' "$1"
  lua5.1 "$1" || exit 1
}

if [ $# -gt 0 ]; then
  run "test/$1"
  exit 0
fi

run test/fzf_tests.lua
run test/shell_tests.lua
run test/termux_tests.lua
run test/translate_tests.lua
run test/commands_tests.lua
run test/dicionario_tests.lua
run test/themes_tests.lua
run test/ipcloop_tests.lua
run test/smoke_tests.lua

echo "TODAS AS SUÍTES OK"