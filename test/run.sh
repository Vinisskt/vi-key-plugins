#!/bin/sh
# Roda a suíte de testes dos plugins (todos os test/*_tests.lua).
# Requer lua5.1 (o mesmo runtime do teclado).
cd "$(dirname "$0")/.." || exit 1
fails=0
for t in test/*_tests.lua; do
  if ! lua5.1 "$t"; then
    fails=1
  fi
  printf "\n"
done
if [ "$fails" -ne 0 ]; then
  echo "SUÍTE FALHOU"
  exit 1
fi
echo "SUÍTE OK"