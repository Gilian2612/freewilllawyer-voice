import hashlib
import hmac
import io
import json
import os
import secrets
import struct
import threading
import time
import uuid
from collections import defaultdict, deque
from pathlib import Path
from fastapi import FastAPI, HTTPException, Request, UploadFile, File
from fastapi.responses import StreamingResponse, HTMLResponse, JSONResponse, RedirectResponse
from pydantic import BaseModel
from piper.config import SynthesisConfig

app = FastAPI(title="Free Will Lawyer Voice API")

VOICES_DIR = Path(__file__).parent / "voices"
STATIC_DIR = Path(__file__).parent / "static"

VOICE_MAP = {
    "en_lessac": VOICES_DIR / "en_US-lessac-medium.onnx",
    "en_amy":    VOICES_DIR / "en_US-amy-medium.onnx",
    "es_sharvard": VOICES_DIR / "es_ES-sharvard-medium.onnx",
    "es_mx":     VOICES_DIR / "es_MX-ald-medium.onnx",
    "en_ryan":   VOICES_DIR / "en_US-ryan-high.onnx",
    "en_cori":   VOICES_DIR / "en_GB-cori-high.onnx",
    "en_ljspeech": VOICES_DIR / "en_US-ljspeech-high.onnx",
    "en_joe":    VOICES_DIR / "en_US-joe-medium.onnx",
    "es_daniela": VOICES_DIR / "es_AR-daniela-high.onnx",
    "es_claude": VOICES_DIR / "es_MX-claude-high.onnx",
    "es_davefx": VOICES_DIR / "es_ES-davefx-medium.onnx",
}

PROFILES = {
    "en": {"name": "Free Will Lawyer", "handle": "freewilllawyer", "lang": "en",
           "voices": ["en_lessac", "en_amy", "en_ryan", "en_cori", "en_ljspeech", "en_joe"], "default_voice": "en_lessac"},
    "es": {"name": "Free Will Lawyer ES", "handle": "freewilllawyer_es", "lang": "es",
           "voices": ["es_sharvard", "es_mx", "es_daniela", "es_claude", "es_davefx"], "default_voice": "es_sharvard"},
}

DATA_DIR = Path(__file__).parent / "data"
SCRIPTS_FILE = DATA_DIR / "scripts.json"
MAX_UPLOAD_BYTES = 2 * 1024 * 1024

_voices = {}
_scripts_lock = threading.Lock()

# --- Access control -------------------------------------------------------
PASSWORD_FILE = DATA_DIR / "password.txt"
SECRET_FILE = DATA_DIR / "secret.key"
COOKIE_NAME = "fwl_session"
COOKIE_MAX_AGE = 30 * 24 * 3600
RATE_LIMIT = 100          # requests per minute, per client IP
LOGIN_LIMIT = 10          # login attempts per minute, per client IP


def _load_password() -> str:
    pw = os.environ.get("FWL_PASSWORD", "").strip()
    if pw:
        return pw
    if PASSWORD_FILE.exists() and PASSWORD_FILE.read_text(encoding="utf-8").strip():
        return PASSWORD_FILE.read_text(encoding="utf-8").strip()
    # No password configured: generate one so the server is never open by default
    pw = secrets.token_urlsafe(6)
    DATA_DIR.mkdir(exist_ok=True)
    PASSWORD_FILE.write_text(pw, encoding="utf-8")
    PASSWORD_FILE.chmod(0o600)
    print(f"\n*** No password was set. Generated access password: {pw}\n"
          f"    (saved in {PASSWORD_FILE}; change it with cambiar-clave.command)\n", flush=True)
    return pw


def _load_secret() -> bytes:
    if not SECRET_FILE.exists():
        DATA_DIR.mkdir(exist_ok=True)
        SECRET_FILE.write_bytes(secrets.token_bytes(32))
        SECRET_FILE.chmod(0o600)
    return SECRET_FILE.read_bytes()


PASSWORD = _load_password()
_SECRET = _load_secret()
# Cookie value depends on the password, so changing the password logs everyone out
SESSION_TOKEN = hmac.new(_SECRET, PASSWORD.encode(), hashlib.sha256).hexdigest()

_hits = defaultdict(deque)
_login_hits = defaultdict(deque)
_rate_lock = threading.Lock()


def _over_limit(store: dict, ip: str, limit: int) -> bool:
    now = time.monotonic()
    with _rate_lock:
        q = store[ip]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= limit:
            return True
        q.append(now)
        if len(store) > 1000:  # drop idle clients
            for k in [k for k, v in store.items() if not v or now - v[-1] > 60]:
                del store[k]
        return False


def _is_authed(request: Request) -> bool:
    return hmac.compare_digest(request.cookies.get(COOKIE_NAME, ""), SESSION_TOKEN)


@app.middleware("http")
async def guard(request: Request, call_next):
    ip = request.client.host if request.client else "unknown"
    if _over_limit(_hits, ip, RATE_LIMIT):
        return JSONResponse({"detail": f"Too many requests (max {RATE_LIMIT}/min). Try again in a minute."},
                            status_code=429, headers={"Retry-After": "60"})
    path = request.url.path
    if path in ("/login", "/health") or _is_authed(request):
        return await call_next(request)
    if request.method == "GET" and path == "/":
        return RedirectResponse("/login")
    return JSONResponse({"detail": "Not authenticated"}, status_code=401)


def load_scripts() -> dict:
    if SCRIPTS_FILE.exists():
        return json.loads(SCRIPTS_FILE.read_text(encoding="utf-8"))
    return {}


def save_scripts(data: dict):
    DATA_DIR.mkdir(exist_ok=True)
    SCRIPTS_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def check_profile(profile: str):
    if profile not in PROFILES:
        raise HTTPException(status_code=404, detail=f"Unknown profile '{profile}'")

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
    noise_scale: float | None = None
    noise_w_scale: float | None = None


class LoginIn(BaseModel):
    password: str


@app.get("/login", response_class=HTMLResponse, include_in_schema=False)
async def login_page():
    return (STATIC_DIR / "login.html").read_text(encoding="utf-8")


@app.post("/login", include_in_schema=False)
async def login(body: LoginIn, request: Request):
    ip = request.client.host if request.client else "unknown"
    if _over_limit(_login_hits, ip, LOGIN_LIMIT):
        return JSONResponse({"detail": "Too many attempts. Wait a minute."}, status_code=429,
                            headers={"Retry-After": "60"})
    if not hmac.compare_digest(body.password.strip().encode(), PASSWORD.encode()):
        return JSONResponse({"detail": "Wrong password"}, status_code=401)
    resp = JSONResponse({"ok": True})
    resp.set_cookie(COOKIE_NAME, SESSION_TOKEN, max_age=COOKIE_MAX_AGE, httponly=True, samesite="lax")
    return resp


@app.post("/logout", include_in_schema=False)
async def logout():
    resp = JSONResponse({"ok": True})
    resp.delete_cookie(COOKIE_NAME)
    return resp


@app.get("/", response_class=HTMLResponse)
async def root():
    html_path = STATIC_DIR / "index.html"
    if html_path.exists():
        return html_path.read_text()
    return HTMLResponse("<h1>Free Will Lawyer Voice Server running</h1>")


@app.get("/health")
async def health():
    return {"status": "ok", "voices_available": list(VOICE_MAP.keys())}


@app.get("/profiles")
async def profiles():
    return PROFILES


class ScriptIn(BaseModel):
    title: str = ""
    text: str


@app.get("/scripts/{profile}")
async def list_scripts(profile: str):
    check_profile(profile)
    with _scripts_lock:
        return load_scripts().get(profile, [])


@app.post("/scripts/{profile}")
async def save_script(profile: str, body: ScriptIn):
    check_profile(profile)
    if not body.text.strip():
        raise HTTPException(status_code=400, detail="Script cannot be empty")
    title = body.title.strip() or body.text.strip().splitlines()[0][:50]
    item = {"id": uuid.uuid4().hex[:10], "title": title, "text": body.text, "updated": int(time.time())}
    with _scripts_lock:
        data = load_scripts()
        data.setdefault(profile, []).insert(0, item)
        save_scripts(data)
    return item


@app.delete("/scripts/{profile}/{script_id}")
async def delete_script(profile: str, script_id: str):
    check_profile(profile)
    with _scripts_lock:
        data = load_scripts()
        data[profile] = [s for s in data.get(profile, []) if s["id"] != script_id]
        save_scripts(data)
    return {"ok": True}


@app.post("/import")
async def import_script(file: UploadFile = File(...)):
    name = file.filename or ""
    ext = Path(name).suffix.lower()
    raw = await file.read(MAX_UPLOAD_BYTES + 1)
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 2 MB)")

    if ext == ".txt":
        for enc in ("utf-8-sig", "cp1252"):
            try:
                text = raw.decode(enc)
                break
            except UnicodeDecodeError:
                continue
    elif ext == ".docx":
        from docx import Document
        try:
            doc = Document(io.BytesIO(raw))
        except Exception:
            raise HTTPException(status_code=400, detail="Could not read the .docx file")
        text = "\n".join(p.text for p in doc.paragraphs)
    else:
        raise HTTPException(status_code=400, detail="Unsupported file type. Use .txt or .docx")

    text = text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="The file has no text")
    return {"title": Path(name).stem, "text": text}


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
        speed = min(max(req.speed, 0.5), 2.0)
        syn_config = SynthesisConfig(
            length_scale=1.0 / speed,
            noise_scale=None if req.noise_scale is None else min(max(req.noise_scale, 0.0), 1.5),
            noise_w_scale=None if req.noise_w_scale is None else min(max(req.noise_w_scale, 0.0), 1.5),
        )
        for chunk in voice.synthesize(req.text, syn_config):
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
