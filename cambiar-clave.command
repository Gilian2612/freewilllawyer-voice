#!/bin/bash
# Sets (or changes) the access password for the voice server. Everyone gets logged out.
# Usage: double-click, or "cambiar-clave.command --quiet" (called by instalar.command).

ROOT="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.freewilllawyer.voice"
QUIET=0; [ "$1" = "--quiet" ] && QUIET=1

pause() { [ "$QUIET" = 1 ] || read -n 1 -s -r -p "Presiona cualquier tecla para cerrar..."; }

PW=$(osascript -e 'text returned of (display dialog "Escribe la nueva contraseña de acceso para el equipo (mínimo 6 caracteres):" default answer "" with hidden answer with title "Free Will Voice" buttons {"Cancelar","Guardar"} default button "Guardar")' 2>/dev/null)
if [ -z "$PW" ]; then echo "Cancelado, no se cambió nada."; pause; exit 1; fi
if [ ${#PW} -lt 6 ]; then
  osascript -e 'display dialog "La contraseña debe tener al menos 6 caracteres." buttons {"OK"} with icon caution' >/dev/null 2>&1
  echo "Contraseña demasiado corta."; pause; exit 1
fi

mkdir -p "$ROOT/data"
printf '%s' "$PW" > "$ROOT/data/password.txt"
chmod 600 "$ROOT/data/password.txt"
echo "Contraseña guardada."

# Restart the service (if installed) so the new password applies
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL" && echo "Servidor reiniciado con la nueva contraseña."
else
  echo "El servicio no está instalado. Si el servidor está corriendo a mano, reinícialo para aplicar la contraseña."
fi
pause
