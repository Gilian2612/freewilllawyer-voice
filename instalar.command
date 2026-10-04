#!/bin/bash
# One-time install (run by the admin): makes the voice server start by itself at login,
# restart if it crashes, keep the Mac awake, and creates the "Free Will Voice" app that
# just opens the interface. The team never needs the Terminal.
# Set DRY_RUN=1 to only generate files without touching launchd.

ROOT="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.freewilllawyer.voice"
PLIST_DIR="${PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$PLIST_DIR/$LABEL.plist"
APP_DIR="${APP_DIR:-$ROOT}"
PORT=8000

fail() { echo ""; echo "ERROR: $1"; echo ""; read -n 1 -s -r -p "Presiona cualquier tecla para cerrar..."; exit 1; }

echo "=== Free Will Lawyer Voice — instalación del servicio ==="

[ -x "$ROOT/venv/bin/python" ] || fail "No existe el venv. Corre primero ./setup.sh"
ls "$ROOT"/voices/*.onnx >/dev/null 2>&1 || fail "No hay voces en voices/. Corre primero ./setup.sh"
"$ROOT/venv/bin/python" -c "import piper.config, docx, fastapi" 2>/dev/null \
  || fail "Faltan dependencias. Corre: source venv/bin/activate && pip install -r requirements.txt"

case "$ROOT" in
  "$HOME/Downloads"*|"$HOME/Desktop"*|"$HOME/Documents"*)
    fail "El proyecto está en una carpeta protegida de macOS ($ROOT). Muévelo a, por ejemplo, $HOME/freewilllawyer-voice y vuelve a correr este archivo desde ahí." ;;
esac

mkdir -p "$ROOT/logs" "$PLIST_DIR"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-is</string>
    <string>$ROOT/venv/bin/python</string>
    <string>$ROOT/main.py</string>
  </array>
  <key>WorkingDirectory</key><string>$ROOT</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>$ROOT/logs/server.log</string>
  <key>StandardErrorPath</key><string>$ROOT/logs/server.log</string>
</dict>
</plist>
PLISTEOF
plutil -lint "$PLIST" >/dev/null || fail "No se pudo generar el plist"
echo "Servicio configurado: $PLIST"

if [ -z "$DRY_RUN" ]; then
  # Stop any server started by hand on this port so the service can take it
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  pkill -f "$ROOT/main.py" 2>/dev/null; pkill -f "python main.py" 2>/dev/null
  sleep 1
  launchctl bootstrap "gui/$(id -u)" "$PLIST" || fail "launchctl no pudo cargar el servicio"
  launchctl enable "gui/$(id -u)/$LABEL"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
fi

# App that opens the interface (and starts the service if it is stopped)
APP="$APP_DIR/Free Will Voice.app"
rm -rf "$APP"
osacompile -o "$APP" <<APPLESCRIPT || fail "No se pudo crear la app"
on isUp()
  try
    do shell script "/usr/bin/curl -fs -m 2 http://localhost:$PORT/health"
    return true
  on error
    return false
  end try
end isUp

on run
  if not isUp() then
    try
      do shell script "/bin/launchctl kickstart gui/\$(id -u)/$LABEL"
    end try
    repeat 20 times
      delay 1
      if isUp() then exit repeat
    end repeat
  end if
  if isUp() then
    open location "http://localhost:$PORT"
  else
    display dialog "El servidor de voz no responde." & return & "Avisa al administrador." & return & "Registro: $ROOT/logs/server.log" buttons {"OK"} default button "OK" with icon caution
  end if
end run
APPLESCRIPT
echo "App creada: $APP"

if [ -z "$DRY_RUN" ]; then
  echo "Esperando a que el servidor responda..."
  for i in $(seq 1 30); do
    curl -fs -m 2 "http://localhost:$PORT/health" >/dev/null && break
    sleep 1
  done
  curl -fs -m 2 "http://localhost:$PORT/health" >/dev/null \
    && echo "Servidor funcionando." \
    || fail "El servidor no arrancó. Revisa $ROOT/logs/server.log"
  open "http://localhost:$PORT"
fi

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "TU_IP")
echo ""
echo "Listo. El servidor arranca solo y se reinicia si falla."
echo "  En esta Mac:      http://localhost:$PORT"
echo "  Para el equipo:   http://$IP:$PORT   (guárdenlo como favorito)"
echo "  Nombre de la Mac: http://$(scutil --get LocalHostName 2>/dev/null || hostname -s).local:$PORT"
echo ""
echo "Pendientes manuales (una sola vez):"
echo "  1. Ajustes > Batería/Energía: impedir reposo automático; Ajustes > Usuarios: inicio de sesión automático,"
echo "     para que el servidor vuelva solo tras un reinicio."
echo "  2. Arrastra 'Free Will Voice.app' al Dock."
echo "  3. Reserva la IP de esta Mac en el router para que no cambie."
echo ""
read -n 1 -s -r -p "Presiona cualquier tecla para cerrar..."
