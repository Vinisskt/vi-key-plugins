#!/bin/sh
# Roda a suíte de testes dos plugins (fzf por enquanto).
# Requer lua5.1 (o mesmo runtime do teclado).
cd "$(dirname "$0")/.." || exit 1
lua5.1 test/fzf_tests.lua