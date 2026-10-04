# Free Will Lawyer — Voice Server

Servidor local de síntesis de voz con Piper TTS. Corre en la MacBook host y el equipo accede desde cualquier dispositivo en la misma red WiFi.

> Las decisiones de diseño, alternativas descartadas y pendientes están en [DECISIONS.md](DECISIONS.md).

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

## Estructura del proyecto

```
freewilllawyer-voice/
├── main.py              # Servidor FastAPI
├── requirements.txt     # Dependencias Python
├── setup.sh             # Script de instalación
├── static/
│   └── index.html       # Interfaz web
├── data/                # Scripts guardados por perfil (se crea solo, no va en git)
└── voices/              # Modelos de voz .onnx + .onnx.json (se llenan con setup.sh)
```

## Uso

- Arriba eliges la cuenta: **Free Will Lawyer** (EN) o **Free Will Lawyer ES**. Cada una muestra sus voces y su lista de scripts guardados.
- **Import .txt / .docx** carga un archivo en el cuadro del script.
- **Speed** cambia la velocidad. **Expressiveness** y **Rhythm variation** controlan cuánta variación tiene la voz (valores bajos = más plana y uniforme, altos = más natural y suelta). Por defecto están en *auto* (valores propios de cada voz); el enlace *(auto)* los restablece.

## Detener el servidor

`Ctrl + C` en la Terminal donde está corriendo.
