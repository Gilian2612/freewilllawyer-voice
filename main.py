import io
import struct
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, HTMLResponse
from pydantic import BaseModel

app = FastAPI(title="Free Will Lawyer Voice API")

VOICES_DIR = Path(__file__).parent / "voices"
STATIC_DIR = Path(__file__).parent / "static"

VOICE_MAP = {
    "en_lessac": VOICES_DIR / "en_US-lessac-medium.onnx",
    "en_amy":    VOICES_DIR / "en_US-amy-medium.onnx",
    "es_sharvard": VOICES_DIR / "es_ES-sharvard-medium.onnx",
    "es_mx":     VOICES_DIR / "es_MX-ald-medium.onnx",
}

_voices = {}

def get_voice(voice_id: str):
    if voice_id not in _voices:
        from piper.voice import PiperVoice
        model_path = VOICE_MAP[voice_id]
        if not model_path.exists():
            raise HTTPException(status_code=503, detail=f"Voice '{voice_id}' not found.")
        _voices[voice_id] = PiperVoice.load(str(model_path))
    return _voices[voice_id]


class TTSRequest(BaseModel):
    text: str
    voice: str = "en_lessac"
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

    voice_id = req.voice if req.voice in VOICE_MAP else "en_lessac"

    try:
        voice = get_voice(voice_id)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    try:
        audio_data = b""
        sample_rate = 22050
        for chunk in voice.synthesize(req.text):
            audio_data += chunk.audio_int16_bytes
            sample_rate = voice.config.sample_rate

        num_channels = 1
        bits_per_sample = 16
        byte_rate = sample_rate * num_channels * bits_per_sample // 8
        block_align = num_channels * bits_per_sample // 8
        data_size = len(audio_data)
        wav = io.BytesIO()
        wav.write(b"RIFF")
        wav.write(struct.pack("<I", 36 + data_size))
        wav.write(b"WAVE")
        wav.write(b"fmt ")
        wav.write(struct.pack("<IHHIIHH", 16, 1, num_channels, sample_rate, byte_rate, block_align, bits_per_sample))
        wav.write(b"data")
        wav.write(struct.pack("<I", data_size))
        wav.write(audio_data)
        wav.seek(0)

        return StreamingResponse(wav, media_type="audio/wav",
                                 headers={"Content-Disposition": "inline; filename=speech.wav"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
