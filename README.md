# Free Will Lawyer — Voice Server

**Language / Idioma:** [English](#english) · [Español](#español)

---

# English

Local text-to-speech server built on Piper TTS. It runs on the host Mac, and the team uses it from any device on the same WiFi network.

> Design decisions, rejected alternatives and open items are in [DECISIONS.md](DECISIONS.md).

## Requirements

- macOS with Python 3.10+
- Internet access only for the initial setup (model downloads)
- All other devices must be on the same WiFi network

## Setup (first time only)

```bash
# 1. Go to the project folder
cd freewilllawyer-voice

# 2. Make the setup script executable
chmod +x setup.sh

# 3. Run the setup (downloads dependencies and voices)
./setup.sh
```

The setup downloads all 11 voices (~860 MB in total, 60–120 MB each). Voices that already exist are skipped.

| Profile | Voice | Model |
|---|---|---|
| Free Will Lawyer (EN) | Lessac (male) | `en_US-lessac-medium` |
| | Amy (female) | `en_US-amy-medium` |
| | Ryan (male, warm) | `en_US-ryan-high` |
| | Cori (UK female, calm) | `en_GB-cori-high` |
| | LJ (female, neutral/formal) | `en_US-ljspeech-high` |
| | Joe (male, deep, announcer-style) | `en_US-joe-medium` |
| Free Will Lawyer ES | Sharvard (ES) | `es_ES-sharvard-medium` |
| | Ald (MX) | `es_MX-ald-medium` |
| | Daniela (AR, female, warm) | `es_AR-daniela-high` |
| | Claude (MX) | `es_MX-claude-high` |
| | Dave (ES, neutral) | `es_ES-davefx-medium` |

### Downloading the voices manually (without `setup.sh`)

From the project folder:

```bash
mkdir -p voices
BASE=https://huggingface.co/rhasspy/piper-voices/resolve/main
for v in \
  en/en_US/lessac/medium/en_US-lessac-medium \
  en/en_US/amy/medium/en_US-amy-medium \
  en/en_US/ryan/high/en_US-ryan-high \
  en/en_GB/cori/high/en_GB-cori-high \
  en/en_US/ljspeech/high/en_US-ljspeech-high \
  en/en_US/joe/medium/en_US-joe-medium \
  es/es_ES/sharvard/medium/es_ES-sharvard-medium \
  es/es_MX/ald/medium/es_MX-ald-medium \
  es/es_AR/daniela/high/es_AR-daniela-high \
  es/es_MX/claude/high/es_MX-claude-high \
  es/es_ES/davefx/medium/es_ES-davefx-medium
do
  n=$(basename $v)
  curl -L --fail -o voices/$n.onnx      $BASE/$v.onnx
  curl -L --fail -o voices/$n.onnx.json $BASE/$v.onnx.json
done
```

To add another voice: download it the same way, add it to `VOICE_MAP` in `main.py` and to the profile's `voices` list (`PROFILES`), and give it a label in `VOICE_LABELS` in `static/index.html`. The full catalog is at https://huggingface.co/rhasspy/piper-voices

## Automatic startup (no Terminal needed for the team)

Designed for a Mac that stays on all the time. The administrator does this **once**, after `./setup.sh`:

1. The project must live in a regular folder, for example `~/freewilllawyer-voice` (**not** in Downloads, Desktop or Documents; macOS blocks background services from reading those).
2. If you downloaded the project as a zip, remove the quarantine flag and set permissions (once):
   ```bash
   cd ~/freewilllawyer-voice
   xattr -dr com.apple.quarantine .
   chmod +x *.command setup.sh
   ```
3. Double-click **`instalar.command`**. It:
   - makes the server start by itself at login and restart if it crashes (`launchd`),
   - keeps the Mac awake while the server runs (`caffeinate`),
   - creates **`Free Will Voice.app`**, which opens the interface (and restarts the server if it was stopped).
4. Drag `Free Will Voice.app` to the Dock.
5. System settings (once): turn off automatic sleep and enable **automatic login** for the user, so the server comes back by itself after a reboot.
6. Reserve the Mac's IP in the router (or use `http://MAC-NAME.local:8000`) and have the team bookmark that URL.

The team only opens the URL in a browser; they don't need the Terminal.

- **Log (if something fails):** `logs/server.log`. From the Terminal: `tail -f ~/freewilllawyer-voice/logs/server.log`
- **Remove automatic startup:** double-click `desinstalar.command`.
- After updating the code (`git pull`), restart the service: `launchctl kickstart -k gui/$(id -u)/com.freewilllawyer.voice`

## Access password and usage limit

- Opening the interface asks for a **shared password** (a single one for the whole team). Each browser remembers it for 30 days.
- `instalar.command` asks for it once in a dialog window. To change it later, double-click **`cambiar-clave.command`** (it restarts the server and signs everyone out).
- It is stored in `data/password.txt` (not tracked by git). It can also be provided through the `FWL_PASSWORD` environment variable.
- If the server starts with no password configured (for example `python main.py` on a fresh clone), it **generates a random one**, prints it in the Terminal and saves it to `data/password.txt`.
- **Limits:** 100 requests per minute per device, and 10 password attempts per minute. Going over returns "Too many requests" and clears by itself after a minute.
- Network security (up to whoever manages the Mac/WiFi): a strong WiFi password and the **macOS firewall turned on** (it is off by default: System Settings → Network → Firewall).

## Running the server by hand (development mode)

```bash
source venv/bin/activate
python main.py
```

The server runs at:
- **Local:** http://localhost:8000
- **Network:** http://YOUR_LOCAL_IP:8000

To find your local IP:
```bash
ipconfig getifaddr en0
```

## Access from other devices

1. All devices must be on the **same WiFi network**
2. Open the browser and go to `http://MACBOOK_IP:8000`
3. Done, nothing to install

## Access from outside the WiFi (Tailscale)

Private access over [Tailscale](https://tailscale.com): only invited devices can reach the server, and traffic is encrypted by Tailscale (the address is plain `http`, no `https` for now).

**On the host Mac (admin, once):**
1. Run `tailscale-activar.command` (double-click). It installs Tailscale only if it is missing (official installer, asks for the Mac's admin password), waits until you sign in, and prints the addresses to use.
2. In the admin panel (https://login.tailscale.com/admin, Machines): turn off key expiry for this Mac and **Share** it with each remote person's email.

**For each remote person:** install Tailscale on their device (https://tailscale.com/download: Mac, Windows, iPhone or Android), accept the invitation and open the address printed by the script, for example `http://MAC_NAME.your-network.ts.net:8000`. The password screen of the app appears.

The Mac must stay on with the voice server running. Do not enable Tailscale *Funnel* (it makes the app public).

Official reference: [Install Tailscale on macOS](https://tailscale.com/docs/install/mac). It requires macOS 12 (Monterey) or later and recommends the *standalone* variant from Tailscale's package server, which is the one `tailscale-activar.command` installs. On first launch, Tailscale's onboarding asks to install its VPN configuration: accept it. The standalone variant also uses a macOS *system extension* that you must approve in System Settings (Privacy & Security); until you do, Tailscale does not start.

**Which Tailscale to install?**
- **Host Mac:** use `tailscale-activar.command` (standalone variant, recommended by Tailscale). The Mac App Store variant should also work, but it has not been tested with the script, which would see it as already installed and skip the installation. Never have both variants installed at the same time; to switch, delete `Tailscale.app`, empty the Trash and restart the Mac.
- **Remote person's device:** any variant on any system works (Mac, Windows, iPhone, Android). The easiest is the app from their device's store or from https://tailscale.com/download.

## Project structure

```
freewilllawyer-voice/
├── main.py                # FastAPI server
├── requirements.txt       # Python dependencies
├── setup.sh               # Installation script (dependencies + voices)
├── instalar.command       # One-time install of the auto-start service + Dock app
├── desinstalar.command    # Removes the auto-start service
├── cambiar-clave.command  # Sets / changes the access password
├── tailscale-activar.command  # Installs Tailscale if missing and prints the remote-access address
├── static/
│   ├── index.html         # Web interface
│   └── login.html         # Password screen
├── data/                  # Saved scripts, password (created automatically, not in git)
├── logs/                  # server.log (created automatically, not in git)
└── voices/                # .onnx + .onnx.json voice models (filled by setup.sh)
```

## Usage

- At the top you pick the account: **Free Will Lawyer** (EN) or **Free Will Lawyer ES**. Each one shows its own voices and its own list of saved scripts.
- **Import .txt / .docx** loads a file into the script box.
- **Speed** changes the speaking rate. **Expressiveness** and **Rhythm variation** control how much variation the voice has (low values = flatter and more uniform, high values = more natural and loose). They default to *auto* (each voice's own values); the *(auto)* link resets them.

## Stopping the server

`Ctrl + C` in the Terminal where it is running.

## Things to keep in mind

- **If you move the project folder, run `instalar.command` again** from the new location. The automatic startup service and the Dock app store the absolute path of the folder; if it is moved, the server will not start after a reboot and the Dock app will not be able to revive it. Voices, data and logs move with the folder without problems.

---

# Español

Servidor local de síntesis de voz con Piper TTS. Corre en la MacBook host y el equipo accede desde cualquier dispositivo en la misma red WiFi.

> Las decisiones de diseño, alternativas descartadas y pendientes están en [DECISIONS.md](DECISIONS.md) (inglés primero, español después).

## Requisitos

- macOS con Python 3.10+
- Conexión a internet solo para el setup inicial (descarga de modelos)
- Los demás dispositivos deben estar en la misma red WiFi

## Setup (solo la primera vez)

```bash
# 1. Entra a la carpeta del proyecto
cd freewilllawyer-voice

# 2. Dale permisos al script de setup
chmod +x setup.sh

# 3. Corre el setup (descarga dependencias y voces)
./setup.sh
```

El setup descarga las 11 voces (~860 MB en total, 60–120 MB cada una). Si una ya existe, la salta.

| Perfil | Voz | Modelo |
|---|---|---|
| Free Will Lawyer (EN) | Lessac (hombre) | `en_US-lessac-medium` |
| | Amy (mujer) | `en_US-amy-medium` |
| | Ryan (hombre, cálido) | `en_US-ryan-high` |
| | Cori (mujer UK, calmada) | `en_GB-cori-high` |
| | LJ (mujer, neutral/formal) | `en_US-ljspeech-high` |
| | Joe (hombre, grave, tipo locutor) | `en_US-joe-medium` |
| Free Will Lawyer ES | Sharvard (ES) | `es_ES-sharvard-medium` |
| | Ald (MX) | `es_MX-ald-medium` |
| | Daniela (AR, mujer, cálida) | `es_AR-daniela-high` |
| | Claude (MX) | `es_MX-claude-high` |
| | Dave (ES, neutral) | `es_ES-davefx-medium` |

### Descargar las voces manualmente (sin `setup.sh`)

Desde la carpeta del proyecto:

```bash
mkdir -p voices
BASE=https://huggingface.co/rhasspy/piper-voices/resolve/main
for v in \
  en/en_US/lessac/medium/en_US-lessac-medium \
  en/en_US/amy/medium/en_US-amy-medium \
  en/en_US/ryan/high/en_US-ryan-high \
  en/en_GB/cori/high/en_GB-cori-high \
  en/en_US/ljspeech/high/en_US-ljspeech-high \
  en/en_US/joe/medium/en_US-joe-medium \
  es/es_ES/sharvard/medium/es_ES-sharvard-medium \
  es/es_MX/ald/medium/es_MX-ald-medium \
  es/es_AR/daniela/high/es_AR-daniela-high \
  es/es_MX/claude/high/es_MX-claude-high \
  es/es_ES/davefx/medium/es_ES-davefx-medium
do
  n=$(basename $v)
  curl -L --fail -o voices/$n.onnx      $BASE/$v.onnx
  curl -L --fail -o voices/$n.onnx.json $BASE/$v.onnx.json
done
```

Para agregar otra voz: descárgala igual, añádela a `VOICE_MAP` en `main.py` y a la lista `voices` del perfil (`PROFILES`), y ponle etiqueta en `VOICE_LABELS` de `static/index.html`. El catálogo completo está en https://huggingface.co/rhasspy/piper-voices

## Arranque automático (sin Terminal para el equipo)

Pensado para una Mac que queda siempre encendida. Se hace **una sola vez** por el administrador, después de `./setup.sh`:

1. El proyecto debe estar en una carpeta normal, por ejemplo `~/freewilllawyer-voice` (**no** en Descargas, Escritorio ni Documentos; macOS bloquea el acceso a servicios en segundo plano).
2. Si bajaste el proyecto como zip, quita la cuarentena y da permisos (una vez):
   ```bash
   cd ~/freewilllawyer-voice
   xattr -dr com.apple.quarantine .
   chmod +x *.command setup.sh
   ```
3. Doble clic en **`instalar.command`**. Esto:
   - hace que el servidor arranque solo al iniciar sesión y se reinicie si se cae (`launchd`),
   - evita que la Mac se duerma mientras el servidor corre (`caffeinate`),
   - crea **`Free Will Voice.app`**, que abre la interfaz (y revive el servidor si estuviera detenido).
4. Arrastra `Free Will Voice.app` al Dock.
5. Ajustes del sistema (una vez): impedir el reposo automático e **inicio de sesión automático** del usuario, para que el servidor vuelva solo tras un reinicio.
6. Reserva la IP de la Mac en el router (o usa `http://NOMBRE-DE-LA-MAC.local:8000`) y que el equipo guarde esa URL como favorito.

El equipo solo abre la URL en el navegador; no necesita Terminal.

- **Registro (si algo falla):** `logs/server.log`. Desde Terminal: `tail -f ~/freewilllawyer-voice/logs/server.log`
- **Quitar el arranque automático:** doble clic en `desinstalar.command`.
- Si actualizas el código (`git pull`), reinicia el servicio: `launchctl kickstart -k gui/$(id -u)/com.freewilllawyer.voice`

## Contraseña de acceso y límite de uso

- Al abrir la interfaz se pide una **contraseña compartida** (una sola para todo el equipo). Queda recordada 30 días en cada navegador.
- `instalar.command` la pide una vez en una ventana. Para cambiarla después: doble clic en **`cambiar-clave.command`** (reinicia el servidor y cierra las sesiones abiertas).
- Se guarda en `data/password.txt` (no va en git). También puede darse con la variable `FWL_PASSWORD`.
- Si el servidor arranca sin contraseña configurada (por ejemplo `python main.py` en un clon nuevo), **genera una al azar**, la muestra en la Terminal y la guarda en `data/password.txt`.
- **Límites:** 100 peticiones por minuto por dispositivo, y 10 intentos de contraseña por minuto. Al pasarse responde "Too many requests" y se libera solo en un minuto.
- Seguridad de red (a cargo de quien administre la Mac/WiFi): clave WiFi fuerte y **firewall de macOS activado** (viene apagado de fábrica: Ajustes del Sistema → Red → Firewall).

## Levantar el servidor a mano (modo desarrollo)

```bash
source venv/bin/activate
python main.py
```

El servidor queda corriendo en:
- **Local:** http://localhost:8000
- **Red:** http://TU_IP_LOCAL:8000

Para ver tu IP local:
```bash
ipconfig getifaddr en0
```

## Acceso desde otros dispositivos

1. Todos deben estar en la **misma red WiFi**
2. Abrir el navegador y entrar a `http://IP_DE_LA_MACBOOK:8000`
3. Listo, sin instalar nada

## Acceso desde fuera del WiFi (Tailscale)

Acceso privado con [Tailscale](https://tailscale.com): solo entran los dispositivos invitados y el tráfico va cifrado por Tailscale (la dirección es `http` simple, sin `https` por ahora).

**En la Mac host (administrador, una vez):**
1. Corre `tailscale-activar.command` (doble clic). Instala Tailscale solo si falta (instalador oficial, pide la contraseña de administrador de la Mac), espera a que inicies sesión y muestra las direcciones a usar.
2. En el panel de administración (https://login.tailscale.com/admin, Machines): desactiva la expiración de la clave de esta Mac y **compártela** (Share) con el correo de cada persona remota.

**Para cada persona remota:** instalar Tailscale en su dispositivo (https://tailscale.com/download: Mac, Windows, iPhone o Android), aceptar la invitación y abrir la dirección que muestra el script, por ejemplo `http://NOMBRE_MAC.tu-red.ts.net:8000`. Aparece la pantalla de contraseña de la app.

La Mac debe seguir encendida con el servidor de voz corriendo. No actives *Funnel* de Tailscale (hace pública la app).

Referencia oficial: [Install Tailscale on macOS](https://tailscale.com/docs/install/mac). Requiere macOS 12 (Monterey) o superior y recomienda la variante *standalone* del servidor de paquetes de Tailscale, que es la que instala `tailscale-activar.command`. En el primer arranque, el asistente de Tailscale pide instalar su configuración de VPN: acéptala. La variante standalone también usa una *extensión de sistema* de macOS que debes aprobar en Ajustes del Sistema (Privacidad y seguridad); mientras no lo hagas, Tailscale no arranca.

**¿Qué Tailscale instalar?**
- **Mac host:** usa `tailscale-activar.command` (variante standalone, la recomendada por Tailscale). La variante de la Mac App Store también debería servir, pero no se probó con el script, que la vería como ya instalada y se saltaría la instalación. Nunca tengas las dos variantes instaladas a la vez; para cambiar, borra `Tailscale.app`, vacía la papelera y reinicia la Mac.
- **Dispositivo de la persona remota:** sirve cualquier variante en cualquier sistema (Mac, Windows, iPhone, Android). Lo más fácil es la app de la tienda de su dispositivo o la de https://tailscale.com/download.

## Estructura del proyecto

```
freewilllawyer-voice/
├── main.py                # Servidor FastAPI
├── requirements.txt       # Dependencias Python
├── setup.sh               # Script de instalación (dependencias + voces)
├── instalar.command       # Instala una vez el servicio de arranque automático + app del Dock
├── desinstalar.command    # Quita el servicio de arranque automático
├── cambiar-clave.command  # Define / cambia la contraseña de acceso
├── tailscale-activar.command  # Instala Tailscale si falta y muestra la dirección de acceso remoto
├── static/
│   ├── index.html         # Interfaz web
│   └── login.html         # Pantalla de contraseña
├── data/                  # Scripts guardados, contraseña (se crea solo, no va en git)
├── logs/                  # server.log (se crea solo, no va en git)
└── voices/                # Modelos de voz .onnx + .onnx.json (se llenan con setup.sh)
```

## Uso

- Arriba eliges la cuenta: **Free Will Lawyer** (EN) o **Free Will Lawyer ES**. Cada una muestra sus voces y su lista de scripts guardados.
- **Import .txt / .docx** carga un archivo en el cuadro del script.
- **Speed** cambia la velocidad. **Expressiveness** y **Rhythm variation** controlan cuánta variación tiene la voz (valores bajos = más plana y uniforme, altos = más natural y suelta). Por defecto están en *auto* (valores propios de cada voz); el enlace *(auto)* los restablece.

## Detener el servidor

`Ctrl + C` en la Terminal donde está corriendo.

## Cosas a tener en cuenta

- **Si mueves la carpeta del proyecto, vuelve a correr `instalar.command`** desde la ubicación nueva. El servicio de arranque automático y la app del Dock guardan la ruta absoluta de la carpeta; si se mueve, el servidor no arrancará tras un reinicio y la app del Dock no podrá revivirlo. Las voces, los datos y los logs se mueven con la carpeta sin problema.
