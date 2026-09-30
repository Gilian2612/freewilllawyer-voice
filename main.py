import os
import io
import subprocess
import tempfile
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

app = FastAPI(title="Free Will Lawyer Voice API")

VOICES_DIR = Path(__file__).parent / "voices"
STATIC_DIR = Path(__file__).parent / "static"

VOICE_MAP = {
    "en": {
        "model": VOICES_DIR / "en_US-lessac-medium.onnx",
        "config": VOICES_DIR / "en_US-lessac-medium.onnx.json",
    },
    "es": {
        "model": VOICES_DIR / "es_ES-sharvard-medium.onnx",
        "config": VOICES_DIR / "es_ES-sharvard-medium.onnx.json",
    },
}


class TTSRequest(BaseModel):
    text: str
    lang: str = "en"
    speed: float = 1.0


@app.get("/", response_class=HTMLResponse)
async def root():
    html_path = STATIC_DIR / "index.html"
    if html_path.exists():
        return html_path.read_text()
    return HTMLResponse("<h1>Free Will Lawyer Voice Server running</h1>")


@app.get("/health")
async def health():
    return {"status": "ok", "voices_available": list(VOICE_MAP.keys())}


@app.post("/speak")
async def speak(req: TTSRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    lang = req.lang if req.lang in VOICE_MAP else "en"
    voice = VOICE_MAP[lang]

    if not voice["model"].exists():
        raise HTTPException(
            status_code=503,
            detail=f"Voice model for '{lang}' not found. Run setup.sh to download voices.",
        )

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        cmd = [
            "piper",
            "--model", str(voice["model"]),
            "--config", str(voice["config"]),
            "--output_file", tmp_path,
            "--length_scale", str(1.0 / req.speed),
        ]
        result = subprocess.run(
            cmd,
            input=req.text.encode("utf-8"),
            capture_output=True,
            timeout=30,
        )

        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=result.stderr.decode())

        audio_bytes = Path(tmp_path).read_bytes()
        return StreamingResponse(
            io.BytesIO(audio_bytes),
            media_type="audio/wav",
            headers={"Content-Disposition": "inline; filename=speech.wav"},
        )

    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
    )
