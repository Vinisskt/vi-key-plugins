#!/data/data/com.termux/files/usr/bin/sh
# install.sh — instala o vi-key-plugins no aparelho.
#   - copia init.lua + plugins/ para /sdcard/keyboard-lua (o que o teclado lê)
#   - garante a pasta de fila data/
#   - compila o daemon (daemon/daemon.c) -> $PREFIX/bin/vk-ipcd (clang nativo)
#   - instala o serviço runit vk-ipc apontando pro binário (fallback Lua)
#   - instala o hook de boot do Termux:Boot (se o app existir)
# uso: sh install.sh
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
KEYBOARD_LUA=/sdcard/keyboard-lua
SERVICE_DIR="$PREFIX/var/service/vk-ipc"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MISSING_DEPS=0

echo "== 1/5 dependências =="
need() { # need <comando> <pacote> <aviso>
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "  falta: $1 ($2) — $3"
    MISSING_DEPS=1
    return 1
  fi
  echo "  ok: $1"
}
need cc clang "o install.sh compila o daemon em C com o clang do Termux"
need sh termux-services "(já vem no Termux; usado pelo runit p/ supervisionar)"
# opcionais com aviso:
command -v trans >/dev/null 2>&1 || {
  echo "  (opcional) trans não instalado — :tr pede: pkg install translate-shell"
}
command -v termux-wake-lock >/dev/null 2>&1 || {
  echo "  (opcional) termux-api não instalado — :battery e :sysinfo melhoram com: pkg install termux-api"
}
command -v curl >/dev/null 2>&1 || {
  echo "  (opcional) curl não instalado — :weather pede: pkg install curl"
}
if [ "$MISSING_DEPS" = 1 ]; then
  echo "!! instale o(s) pacote(s) que faltam e rode de novo: pkg install clang ..."
  exit 1
fi

echo "== 2/5 copiando plugins p/ $KEYBOARD_LUA =="
mkdir -p "$KEYBOARD_LUA/plugins" "$KEYBOARD_LUA/data"
cp "$SCRIPT_DIR/init.lua" "$KEYBOARD_LUA/"
cp "$SCRIPT_DIR"/plugins/*.lua "$KEYBOARD_LUA/plugins/"

echo "== 3/5 compilando daemon =="
cc -O2 -Wall -Wextra -o "$PREFIX/bin/vk-ipcd" "$SCRIPT_DIR/daemon/daemon.c"

echo "== 4/5 serviço runit vk-ipc =="
mkdir -p "$SERVICE_DIR/log"
mkdir -p "$SERVICE_DIR/supervise"
cat > "$SERVICE_DIR/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
if [ -x "$PREFIX/bin/vk-ipcd" ]; then exec "$PREFIX/bin/vk-ipcd"; fi
exec /data/data/com.termux/files/usr/bin/lua5.1 $KEYBOARD_LUA/plugins/ipc-loop.lua --daemon
EOF
chmod +x "$SERVICE_DIR/run"
# log do serviço (runit pode reclamar se não existir; simples é o suficiente)
if [ ! -x "$SERVICE_DIR/log/run" ]; then
cat > "$SERVICE_DIR/log/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec /data/data/com.termux/files/usr/bin/vlogger -t vk-ipc 2>/dev/null || exec svlogd -tt "$SERVICE_DIR/log"
EOF
chmod +x "$SERVICE_DIR/log/run"
fi

echo "== 5/5 boot hook (Termux:Boot) =="
mkdir -p "$HOME_DIR/.termux/boot"
cat > "$HOME_DIR/.termux/boot/vk-ipc.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
# Inicia o serviço vk-ipc junto com o termux-services (requer Termux:Boot).
export HOME=$HOME_DIR
sleep 2
exec sv start vk-ipc
EOF
chmod +x "$HOME_DIR/.termux/boot/vk-ipc.sh"

# Reinicia o serviço limpo.
rm -f "$KEYBOARD_LUA/data/busy" "$KEYBOARD_LUA/data/cmd"
if command -v sv >/dev/null 2>&1 && [ -d "$SERVICE_DIR" ]; then
  sv stop vk-ipc 2>/dev/null || true
  if sv start vk-ipc; then
    echo "ok — serviço vk-ipc ativo ($PREFIX/bin/vk-ipcd)"
    echo "heartbeat: $(( $(date +%s) - $(stat -c %Y "$KEYBOARD_LUA/data/heartbeat" 2>/dev/null || echo 0) ))s atrás"
  fi
else
  echo "aviso: runit/sv não encontrado; rode o daemon na mão: $PREFIX/bin/vk-ipcd"
fi

echo "ok — instale/conceda acesso ao teclado vi-key (armazenamento) e use :termux echo oi"