# Free Will Lawyer Voice — Decision log / Registro de decisiones

**Language / Idioma:** [English](#english) · [Español](#español)

---

# English

This document records **what was built, why, which alternatives were rejected and what is still open**. Usage instructions are in [README.md](README.md).

> **How it was built.** The project was developed in working sessions with Claude Code (Anthropic's AI assistant). The assistant proposed options, wrote code and ran tests; **the project author defined the goal, chose between the options and set the scope limits** (see "Who decided what"). The test results quoted here are the ones that were run during the session; anything that could not be verified is marked as such.

---

## 1. The problem

Original request from the client (a law firm with two Instagram accounts, *Free Will Lawyer* and *Free Will Lawyer ES*):

> "Please set up a voice AI for me that can read scripts that we have on Instagram."

Requirements derived from the conversation:
- Synthetic voice that reads scripts in **English and Spanish**, one account per language.
- Used by a **non-technical team** from the browser, with nothing to install.
- Scripts may be **confidential** (law firm) → privacy and access control matter.
- Runs on a **client Mac that is always on**.

## 2. Baseline: a local server with Piper TTS

**Decision: local speech synthesis with [Piper](https://github.com/rhasspy/piper) + FastAPI**, rather than a cloud service.

| Criterion | Local (Piper) | Cloud (e.g. ElevenLabs) |
|---|---|---|
| Cost | Free | Pay per use |
| Script privacy | Text never leaves the network | Text is sent to a third party |
| Quality / emotion | Good, no emotion control | More expressive |
| Internet dependency | Only for setup | Always |

The lack of expressiveness was accepted in exchange for zero cost and privacy. Piper has no "serious vs. casual" tone control; the closest thing is two variation parameters (see §5).

## 3. "Linking an account": three levels, the simplest was chosen

Three levels of Instagram integration were laid out:

1. **Accounts as profiles** in the interface (EN / ES selector, each with its own voices and scripts).
2. Import scripts from Instagram through the Graph API (needs Business/Creator accounts, a Facebook page and a Meta app; only useful if the scripts live in the captions).
3. Publish the audio back to Instagram.

**Author's decision:** drop 3, build 1, and keep 2 as a future option. Reason: 1 covers the real use without depending on Meta permissions, and it was not known whether the scripts live on Instagram.

**Importing scripts from a file (`.txt` / `.docx`):** added at the author's request as an alternative to level 2.
- 2 MB cap, text read in memory (the file is never stored or executed).
- `.docx` through `python-docx` (paragraphs are read; **tables are not**). `.doc` and PDF are rejected with a clear error.
- `.txt` accepts UTF-8 and Windows-1252 so accents and ñ don't break.

**Saved scripts live on the server** (`data/scripts.json`, per profile), not in the browser, so every device on the network sees the same list. Cost: each server has its own list.

## 4. A bug found along the way: the speed slider did nothing

While reviewing the code it turned out that `speed` reached the server and was never passed to Piper. Fixed with `length_scale = 1 / speed` (clamped to 0.5×–2×).

**Verification, and a testing mistake.** The first test gave inconsistent audio sizes (at 0.6× the audio came out shorter than at 1.0×). Cause: **an old server was still holding port 8000**, so the test never reached the new code. It was caught because `/health` listed fewer voices than expected. After stopping the old server the relationship was correct (0.6× → 136 KB, 1.0× → 95 KB, 1.6× → 64 KB). Since then tests run on **a different port (8001)** so they don't depend on what is running on 8000.

## 5. Voices: selection criteria

6 voices were added to the 4 original ones (11 in total, counting Joe), looking for **different warmth** in the Piper catalog, 3 per language, favoring `high` quality.

**Variation control ("temperature"-style).** Two parameters were exposed: `noise_scale` (expressiveness) and `noise_w_scale` (rhythm variation). **Design decision:** the default is *auto* (`null` is sent and Piper uses each voice's own value), because defaults differ between voices and forcing one would change the sound without the user asking for it.

**Deep announcer-style voice.** The assistant cannot "listen", so instead of choosing blindly the **fundamental frequency (F0)** of the male candidates was measured by autocorrelation:

| Voice | Approx. F0 |
|---|---|
| en_GB-alan-medium | 90 Hz |
| **en_US-joe-medium** (chosen) | 98 Hz |
| en_US-norman-medium | 100 Hz |
| other existing male voices | 119–171 Hz |

In Spanish the catalog has **no** voice deeper than the existing ones (≈120 Hz); the alternative would be lowering the pitch with audio processing, which can sound artificial. Left undone.

**Honest limitations:** the warmth choices were based on the catalog and the pitch measurement, **not on human listening**, and must be confirmed by ear. The measurement suggested that the "Lessac (Male)" label is wrong (193 Hz, similar to Amy) — **still to be fixed**.

## 6. Deployment: from "run a .sh" to "never touch the Terminal"

**Author's requirement:** the team is not used to the Terminal, so any contact with it had to be avoided.

Options evaluated: a `.command` file, an Automator app, an AppleScript app, `launchd`.

**Decision: `launchd` + a Dock app that only opens the interface.** Reasoning:
- The Mac is **always on** → a service that starts by itself and restarts on failure fits better than a button that starts the server.
- Automator "saves work" only in appearance: the logic (don't start twice, wait for `/health`, open the browser) has to be written anyway, and an Automator app with no log is hard to debug. The service writes to `logs/server.log`, readable from the Terminal if something fails.
- `Free Will Voice.app` is generated with `osacompile` on each Mac (not versioned). It restarts the service if stopped, and if the server doesn't answer it shows a dialog with the log path, no Terminal needed.

**Author's decision:** keep `setup.sh` (installs dependencies and voices) and `instalar.command` (installs the service) **as two separate steps**. Merging them (one double-click) was weighed against its costs: errors that are harder to locate, an ~860 MB download with no clear progress signal, and repeating steps on reinstall.

**Real problems found and how they were resolved:**
- **`piper-tts` was not in `requirements.txt`.** It worked on the development machine because it had been installed by hand in the `venv`; on the client's Mac it failed with `No module named 'piper.config'` (the binary's `piper/` folder shadowed the package). The dependency was added. *Lesson: test in a clean environment, not just the development one.*
- **macOS protected folders.** A background service cannot read `~/Downloads`, Desktop or Documents. `instalar.command` detects those paths and stops with a clear message instead of failing silently.

**Limits that code cannot fix:** automatic login after a reboot (a LaunchAgent needs a session), the Mac not going to sleep, and a fixed IP in the router. They are documented in the README.

## 7. Security

A review was done of what someone on the same WiFi could do, **by reading the code**, not by assuming:

- **Cannot** read files on the Mac or run commands: the API has no route that reads or writes arbitrary files, and no static folder is mounted.
- **Could** (before the password): read, change and delete the saved scripts; flood the server with no limit; and see the traffic (unencrypted HTTP).

**Author's decision:** implement **only** (a) an access password and (b) **100 requests per minute**; the rest (WiFi password, firewall) is up to whoever manages the network.

Implementation:
- A single shared password; a 30-day session cookie signed with HMAC (`httponly`, `samesite=lax`). Changing the password invalidates every session.
- With no password configured, the server **generates a random one** at startup: it is never open by default.
- Limit of 100 requests/min per IP and **10 login attempts/min** per IP (against brute force).
- `cambiar-clave.command` to reset it without the Terminal (dialog with hidden input).
- Verified with `curl`: no session → `401`, with session → `200`, request 101 gets `429`, and the project files (`.command`, `main.py`, `data/…`, `../` attempts) are **not reachable** even with a session.

**Correction about the firewall.** It had been assumed that the macOS firewall was on; it is actually **off by default**. This was corrected and documented as an administrator task.

**An unrequested measure, reverted.** The assistant disabled FastAPI's `/docs` without being asked. The author asked to turn it back on **excluding the authentication endpoints** from the schema (`include_in_schema=False`); `/docs` remains behind the login.

## 8. Access from outside the network (not implemented yet)

Evaluated: **Tailscale** (private VPN), **Cloudflare Tunnel** and **ngrok**; none of them needs ports opened in the router (the Mac makes the outbound connection).

**Recommendation for the current case (one person in another country): Tailscale**: only invited devices get in, traffic is end-to-end encrypted (important with confidential scripts) and it is free at this size. Cloudflare/ngrok mean exposing a public URL and sending traffic through a third party.

**Technical implication identified in advance:** behind a public tunnel, every request reaches the server from `127.0.0.1`, so the per-IP limit would become **shared by everyone** and an attacker could lock the team out of the login. The real IP would have to be read from the tunnel's headers. With Tailscale this problem does not appear.

Prices were quoted from memory and must be confirmed on the official pages.

## 9. Who decided what

| Decision | Who |
|---|---|
| Drop publishing to Instagram; build profiles + file import | Author |
| Look for voices with different warmth, 3 per language, plus a deep announcer voice | Author (criteria) / Assistant (selection and measurement) |
| Keep the team away from the Terminal; Mac always on | Author (requirement) |
| `launchd` + Dock app instead of Automator alone | Assistant proposed, author approved |
| `setup.sh` and `instalar.command` kept separate | Author |
| Only password + 100 req/min (nothing else) | Author |
| Re-enable `/docs` without the login endpoints | Author (corrected an assistant measure) |
| Tests on port 8001; verification with `curl` | Assistant |

## 10. Open items and known limitations

- **Not verified end to end by the assistant:** automatic restart after reboot/logout and the "server stopped → the app revives it" case (the author tested the installation on the client's Mac).
- An unknown `voice` in `/speak` **silently falls back to `en_lessac`** instead of returning an error.
- `speed` and the noise parameters are applied, but there is **no text size limit** on `/speak`.
- Possibly wrong Lessac label (§5); no deep voice in Spanish.
- Dependencies pinned from 2024 (FastAPI, `python-multipart`): they should be updated.
- No favicon (it causes a harmless 404 in the log).
- Remote access (§8) not implemented.
- Importing directly from Instagram (level 2) not implemented.

## 11. Commit timeline

| Commit | Change |
|---|---|
| `2d3d8e6` | Initial setup: Piper TTS server |
| `55404d2` | 4-voice selector |
| `41e5afd` | Profiles, import, 6 new voices, speed and variation |
| `03e7909` | Fix: `piper-tts` was missing from `requirements.txt` |
| `9b01ad1` | Automatic startup (`launchd`), Dock app, installers |
| `f39c9d4` | Access password and request limit |

---

# Español

Este documento cuenta **qué se construyó, por qué, qué alternativas se descartaron y qué falta**. Las instrucciones de uso están en [README.md](README.md).

> **Cómo se construyó.** El proyecto se desarrolló en sesiones de trabajo con Claude Code (asistente de IA de Anthropic). El asistente propuso opciones, escribió código y ejecutó pruebas; **el autor del proyecto definió el objetivo, eligió entre las opciones y fijó los límites de alcance** (ver "Quién decidió qué"). Los resultados de pruebas citados aquí son los que se ejecutaron en la sesión; lo que no se pudo verificar está marcado como tal.

---

## 1. El problema

Pedido original del cliente (despacho de abogados con dos cuentas de Instagram, *Free Will Lawyer* y *Free Will Lawyer ES*):

> "Please set up a voice AI for me that can read scripts that we have on Instagram."

Requisitos que se derivaron de la conversación:
- Voz sintética que lea guiones en **inglés y español**, una cuenta por idioma.
- Que lo use un **equipo no técnico** desde el navegador, sin instalar nada.
- Los guiones pueden ser **confidenciales** (despacho legal) → privacidad y control de acceso importan.
- Corre en una **Mac del cliente que siempre está encendida**.

## 2. Línea base: servidor local con Piper TTS

**Decisión: síntesis de voz local con [Piper](https://github.com/rhasspy/piper) + FastAPI**, en vez de un servicio en la nube.

| Criterio | Local (Piper) | Nube (p. ej. ElevenLabs) |
|---|---|---|
| Costo | Gratis | Pago por uso |
| Privacidad de los guiones | El texto nunca sale de la red | El texto se envía a un tercero |
| Calidad / emoción | Buena, sin control de emoción | Mayor expresividad |
| Dependencia de internet | Solo para el setup | Siempre |

Se aceptó la limitación de expresividad a cambio de costo cero y privacidad. Piper no tiene control de "tono serio vs. casual"; lo más cercano son dos parámetros de variación (ver §5).

## 3. "Vincular con una cuenta": tres niveles, se eligió el más simple

Se plantearon tres niveles de integración con Instagram:

1. **Cuentas como perfiles** en la interfaz (selector EN / ES con voces y guiones propios).
2. Importar guiones desde Instagram con la Graph API (requiere cuentas Business/Creator, página de Facebook y app de Meta; solo sirve si los guiones están en los captions).
3. Publicar el audio de vuelta en Instagram.

**Decisión del autor:** descartar el 3, hacer el 1 y dejar el 2 como futuro. Razón: el 1 resuelve el uso real sin depender de permisos de Meta, y no se sabía si los guiones viven en Instagram.

**Importar guiones desde archivo (`.txt` / `.docx`):** se añadió a petición del autor como alternativa al nivel 2.
- Tope de 2 MB, texto leído en memoria (nunca se guarda ni ejecuta el archivo).
- `.docx` con `python-docx` (se leen párrafos; **las tablas no**). `.doc` y PDF se rechazan con un error claro.
- `.txt` acepta UTF-8 y Windows-1252 para no romper tildes y ñ.

**Guiones guardados en el servidor** (`data/scripts.json`, por perfil), no en el navegador, para que todos los dispositivos de la red vean lo mismo. Costo: cada servidor tiene su propia lista.

## 4. Un bug encontrado a mitad de camino: el slider de velocidad no hacía nada

Al revisar el código se vio que `speed` llegaba al servidor y nunca se pasaba a Piper. Se corrigió con `length_scale = 1 / speed` (limitado a 0.5×–2×).

**Verificación y un error de método.** La primera prueba dio tamaños de audio incoherentes (a 0.6× salía más corto que a 1.0×). Causa: **había un servidor viejo ocupando el puerto 8000**, así que la prueba nunca llegó al código nuevo. Se detectó porque `/health` listaba menos voces de las esperadas. Tras apagar el servidor viejo la relación fue la correcta (0.6× → 136 KB, 1.0× → 95 KB, 1.6× → 64 KB). Desde entonces las pruebas se corren en **otro puerto (8001)** para no depender de lo que haya en el 8000.

## 5. Voces: criterio de elección

Se añadieron 6 voces a las 4 iniciales (11 en total, con Joe), buscando **distinta calidez** en el catálogo de Piper, 3 por idioma, priorizando calidad `high`.

**Control de variación (estilo "temperature").** Se expusieron `noise_scale` (expresividad) y `noise_w_scale` (variación de ritmo). **Decisión de diseño:** el valor por defecto es *auto* (se envía `null` y Piper usa el valor propio de cada voz), porque los valores por defecto difieren entre voces y forzar uno cambiaría el sonido sin que el usuario lo pida.

**Voz grave tipo locutor.** No hay forma de "escuchar" desde el asistente, así que se **midió la frecuencia fundamental (F0)** de los candidatos masculinos por autocorrelación en vez de elegir a ciegas:

| Voz | F0 aprox. |
|---|---|
| en_GB-alan-medium | 90 Hz |
| **en_US-joe-medium** (elegida) | 98 Hz |
| en_US-norman-medium | 100 Hz |
| otras voces masculinas existentes | 119–171 Hz |

En español **no hay** una voz más grave que las existentes (≈120 Hz) en el catálogo; la alternativa sería bajar el tono con procesamiento, que puede sonar artificial. Quedó sin hacer.

**Limitaciones honestas:** la elección de calidez se basó en el catálogo y en la medición de tono, **no en escucha humana**; debe confirmarse a oído. La medición sugirió que la etiqueta "Lessac (Male)" es incorrecta (193 Hz, similar a Amy) — **pendiente de corregir**.

## 6. Despliegue: de "correr un .sh" a "no tocar la Terminal"

**Requisito del autor:** el equipo no está acostumbrado a la Terminal; había que evitarles cualquier contacto con ella.

Opciones evaluadas: archivo `.command`, app de Automator, app de AppleScript, `launchd`.

**Decisión: `launchd` + una app de Dock que solo abre la interfaz.** Razonamiento:
- La Mac **siempre está encendida** → un servicio que arranca solo y se reinicia es más adecuado que un botón para levantar el servidor.
- Automator "ahorra trabajo" solo en apariencia: la lógica (no duplicar procesos, esperar a `/health`, abrir el navegador) hay que escribirla igual, y una app de Automator sin log es difícil de depurar. El servicio escribe en `logs/server.log`, visible desde la Terminal si algo falla.
- `Free Will Voice.app` se genera con `osacompile` en cada Mac (no se versiona), y revive el servicio si está detenido; si no responde, muestra un diálogo con la ruta del log, sin Terminal.

**Decisión del autor:** mantener `setup.sh` (instala dependencias y voces) e `instalar.command` (instala el servicio) **como dos pasos separados**. Se pesó fusionarlos (un doble clic) contra los costos: errores más difíciles de ubicar, una descarga de ~860 MB sin señal clara de progreso, y repetir pasos al reinstalar.

**Problemas reales encontrados y su resolución:**
- **`piper-tts` no estaba en `requirements.txt`.** Funcionaba en la máquina de desarrollo porque se había instalado a mano en el `venv`; en la Mac del cliente falló con `No module named 'piper.config'` (la carpeta `piper/` del binario ocultaba al paquete). Se agregó la dependencia. *Lección: probar en un entorno limpio, no solo en el de desarrollo.*
- **Carpetas protegidas de macOS.** Un servicio en segundo plano no puede leer `~/Downloads`, Escritorio ni Documentos. `instalar.command` detecta esas rutas y se detiene con un mensaje claro en vez de fallar en silencio.

**Límites que no se pueden resolver desde el código:** inicio de sesión automático tras reiniciar (un LaunchAgent necesita sesión), que la Mac no entre en reposo, y IP fija en el router. Quedan documentados en el README.

## 7. Seguridad

Se hizo una revisión de lo que podría hacer alguien conectado a la misma WiFi, **leyendo el código**, no suponiendo:

- **No puede** leer archivos de la Mac ni ejecutar comandos: la API no tiene ninguna ruta que lea o escriba archivos arbitrarios, y no se monta ninguna carpeta estática.
- **Sí podía** (antes de la contraseña): leer, cambiar y borrar los guiones guardados; saturar el servidor sin límite; y ver el tráfico (HTTP sin cifrar).

**Decisión del autor:** implementar **solo** (a) contraseña de acceso y (b) **100 peticiones por minuto**; el resto (clave de WiFi, firewall) depende de quien administre la red.

Implementación:
- Una contraseña compartida; cookie de sesión de 30 días firmada con HMAC (`httponly`, `samesite=lax`). Cambiar la contraseña invalida todas las sesiones.
- Sin contraseña configurada, el servidor **genera una aleatoria** al arrancar: nunca queda abierto por defecto.
- Límite de 100 peticiones/min por IP y de **10 intentos de login/min** por IP (contra fuerza bruta).
- `cambiar-clave.command` para restablecerla sin Terminal (diálogo con entrada oculta).
- Verificado con `curl`: sin sesión `401`, con sesión `200`, la petición 101 recibe `429`, y los archivos del proyecto (`.command`, `main.py`, `data/…`, intentos de `../`) **no son accesibles** ni con sesión.

**Corrección sobre el firewall.** Se había asumido que el firewall de macOS venía activo; en realidad **viene apagado de fábrica**. Se corrigió y se documentó como tarea del administrador.

**Una medida de más, revertida.** El asistente desactivó `/docs` de FastAPI sin que se pidiera. El autor pidió reactivarlo **excluyendo los endpoints de autenticación** del esquema (`include_in_schema=False`); `/docs` sigue detrás del login.

## 8. Acceso desde fuera de la red (pendiente de implementar)

Evaluadas: **Tailscale** (VPN privada), **Cloudflare Tunnel** y **ngrok**; ninguna requiere abrir puertos en el router (la Mac inicia la conexión hacia afuera).

**Recomendación para el caso actual (una persona en otro país): Tailscale**: solo entran dispositivos invitados, el tráfico va cifrado de extremo a extremo (importante con guiones confidenciales) y es gratis para este tamaño. Cloudflare/ngrok implican exponer una URL pública y pasar el tráfico por un tercero.

**Implicación técnica identificada de antemano:** detrás de un túnel público, todas las peticiones llegan al servidor desde `127.0.0.1`, así que el límite por IP pasaría a ser **compartido por todos** y un atacante podría bloquear el login del equipo. Habría que leer la IP real de las cabeceras del túnel. Con Tailscale este problema no aparece.

Los precios se citaron de memoria y deben confirmarse en las páginas oficiales.

## 9. Quién decidió qué

| Decisión | Quién |
|---|---|
| Descartar publicar en Instagram; hacer perfiles + importar archivos | Autor |
| Buscar voces con distinta calidez, 3 por idioma, y una voz grave de locutor | Autor (criterio) / Asistente (selección y medición) |
| Evitar la Terminal para el equipo; Mac siempre encendida | Autor (requisito) |
| `launchd` + app de Dock en vez de solo Automator | Asistente propuso, autor aprobó |
| `setup.sh` e `instalar.command` separados | Autor |
| Solo contraseña + 100 req/min (nada más) | Autor |
| Reactivar `/docs` sin endpoints de login | Autor (corrigió una medida del asistente) |
| Pruebas en puerto 8001; verificación con `curl` | Asistente |

## 10. Pendientes y limitaciones conocidas

- **No verificado de punta a punta por el asistente:** el reinicio automático tras reboot/cierre de sesión y el caso "servidor detenido → la app lo revive" (el autor probó la instalación en la Mac del cliente).
- Un `voice` desconocido en `/speak` **cae en silencio a `en_lessac`** en vez de devolver error.
- `speed` y los parámetros de ruido se aplican, pero no hay **límite de tamaño de texto** en `/speak`.
- Etiqueta de Lessac posiblemente incorrecta (§5); sin voz grave en español.
- Dependencias fijadas de 2024 (FastAPI, `python-multipart`): conviene actualizarlas.
- Sin favicon (genera un 404 inofensivo en el log).
- Acceso remoto (§8) sin implementar.
- Importación directa desde Instagram (nivel 2) sin implementar.

## 11. Cronología resumida (commits)

| Commit | Cambio |
|---|---|
| `2d3d8e6` | Setup inicial: servidor Piper TTS |
| `55404d2` | Selector de 4 voces |
| `41e5afd` | Perfiles, importación, 6 voces nuevas, velocidad y variación |
| `03e7909` | Corrección: `piper-tts` faltaba en `requirements.txt` |
| `9b01ad1` | Arranque automático (`launchd`), app del Dock, instaladores |
| `f39c9d4` | Contraseña de acceso y límite de peticiones |
