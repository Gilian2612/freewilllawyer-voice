# Free Will Lawyer — Voice Server

Servidor local de síntesis de voz con Piper TTS. Corre en la MacBook host y el equipo accede desde cualquier dispositivo en la misma red WiFi.

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

El setup descarga dos modelos de voz (~130 MB cada uno):
- Inglés: `en_US-lessac-medium`
- Español: `es_ES-sharvard-medium`

## Levantar el servidor

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
└── voices/              # Modelos de voz (se llenan con setup.sh)
    ├── en_US-lessac-medium.onnx
    ├── en_US-lessac-medium.onnx.json
    ├── es_ES-sharvard-medium.onnx
    └── es_ES-sharvard-medium.onnx.json
```

## Detener el servidor

`Ctrl + C` en la Terminal donde está corriendo.
