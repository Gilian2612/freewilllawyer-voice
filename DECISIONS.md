# Registro de decisiones — Free Will Lawyer Voice

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
