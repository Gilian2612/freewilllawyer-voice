#!/bin/bash
# Sets up private access from outside the WiFi with Tailscale (run by the admin on the host Mac).
# Safe to run more than once: installs Tailscale only if it is missing, then shows the address.
# Plain HTTP over the private Tailscale network (traffic is already encrypted by Tailscale).
# Set DRY_RUN=1 to only show what it would do.

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/Tailscale.app"
CLI="$APP/Contents/MacOS/Tailscale"
BASE_URL="https://pkgs.tailscale.com/stable"
PORT=8000

pause() { echo ""; read -n 1 -s -r -p "Presiona cualquier tecla para cerrar..."; }
fail() { echo ""; echo "ERROR: $1"; pause; exit 1; }

echo "=== Free Will Lawyer Voice — acceso privado con Tailscale ==="
echo ""

# 1. Install Tailscale if it is missing
if [ -d "$APP" ]; then
  echo "Tailscale ya está instalado, se omite la instalación."
elif [ -n "$DRY_RUN" ]; then
  echo "[DRY_RUN] Tailscale no está instalado: se descargaría el instalador oficial de $BASE_URL"
else
  echo "Tailscale no está instalado. Descargando el instalador oficial..."
  PKG_NAME=$(curl -fsS -m 30 "$BASE_URL/" | grep -o 'Tailscale-[0-9.]*-macos\.pkg' | head -1)
  [ -n "$PKG_NAME" ] || fail "No se pudo averiguar la última versión. Instálalo a mano desde https://tailscale.com/download y vuelve a correr este archivo."
  PKG="$(mktemp -d)/$PKG_NAME"
  curl -fL --progress-bar -o "$PKG" "$BASE_URL/$PKG_NAME" || fail "No se pudo descargar $PKG_NAME."
  pkgutil --check-signature "$PKG" 2>&1 | grep -qi "tailscale" \
    || fail "El instalador descargado no tiene la firma de Tailscale. No se instaló."
  echo "Instalando (te pedirá la contraseña de administrador de la Mac)..."
  sudo installer -pkg "$PKG" -target / >/dev/null || fail "La instalación falló."
  rm -f "$PKG"
  echo "Tailscale instalado."
fi

[ -n "$DRY_RUN" ] && { echo "[DRY_RUN] Terminaría aquí."; pause; exit 0; }

# 2. Open the app and wait until the account is signed in
if ! "$CLI" status >/dev/null 2>&1; then
  echo ""
  echo "Abriendo Tailscale. Inicia sesión con tu cuenta en la ventana/navegador que aparece."
  echo "Si macOS pide aprobar una configuración de VPN o extensión, acéptala (Ajustes del Sistema)."
  open -a Tailscale
  for _ in $(seq 1 90); do
    "$CLI" status >/dev/null 2>&1 && break
    sleep 2
  done
  "$CLI" status >/dev/null 2>&1 || fail "Tailscale no quedó conectado tras 3 minutos. Inicia sesión en la app y vuelve a correr este archivo."
fi
echo "Tailscale conectado."

# 3. Work out the address other devices must use
IP=$("$CLI" ip -4 2>/dev/null | head -1)
NAME=$("$CLI" status --json 2>/dev/null | "$ROOT/venv/bin/python" -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null)

# 4. Is the voice server answering?
if curl -fs -m 3 "http://localhost:$PORT/health" >/dev/null; then
  echo "El servidor de voz responde en el puerto $PORT."
else
  echo "AVISO: el servidor de voz no responde en el puerto $PORT. Arráncalo (python main.py o instalar.command) antes de probar."
fi

echo ""
echo "Direcciones para entrar desde un dispositivo con Tailscale (HTTP, sin https):"
[ -n "$NAME" ] && echo "  http://$NAME:$PORT"
[ -n "$IP" ]   && echo "  http://$IP:$PORT"
echo ""
echo "Falta, una sola vez y a mano, en https://login.tailscale.com/admin :"
echo "  - Machines: desactivar la expiración de la clave de esta Mac."
echo "  - Machines: compartir esta Mac (Share) con el correo de cada persona remota."
echo "  - La persona remota instala Tailscale (https://tailscale.com/download), acepta la invitación y abre la dirección de arriba."
pause
