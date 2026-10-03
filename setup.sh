#!/bin/bash
# Setup script for Free Will Lawyer Voice Server
# Run this on the host MacBook before starting the server

set -e

echo "=== Free Will Lawyer Voice Server Setup ==="
echo ""

# Check Python
if ! command -v python3 &>/dev/null; then
  echo "ERROR: Python 3 not found. Install it from https://python.org"
  exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Python $PYTHON_VERSION detected"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
  echo "Creating virtual environment..."
  python3 -m venv venv
fi

# Activate venv
source venv/bin/activate
echo "Virtual environment activated"

# Install dependencies
echo ""
echo "Installing dependencies..."
pip install --upgrade pip -q
pip install -r requirements.txt -q
echo "Dependencies installed"

# Download Piper binary (native build; the pip package has no wheels for Python 3.14)
echo ""
PIPER_VERSION="2023.11.14-2"
if [ ! -x "piper/piper" ]; then
  echo "Downloading Piper binary..."
  curl -L -o piper_macos_aarch64.tar.gz \
    "https://github.com/rhasspy/piper/releases/download/$PIPER_VERSION/piper_macos_aarch64.tar.gz"
  tar -xzf piper_macos_aarch64.tar.gz
  rm piper_macos_aarch64.tar.gz
  xattr -dr com.apple.quarantine piper 2>/dev/null || true
  echo "Piper binary installed at ./piper/piper"
else
  echo "Piper binary already present, skipping"
fi

# Download voice models
echo ""
echo "Downloading voice models (this may take a few minutes)..."
mkdir -p voices

BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main"

# Voices: <lang>/<locale>/<speaker>/<quality>/<full-name>
VOICES=(
  "en/en_US/lessac/medium/en_US-lessac-medium"
  "en/en_US/amy/medium/en_US-amy-medium"
  "en/en_US/ryan/high/en_US-ryan-high"
  "en/en_GB/cori/high/en_GB-cori-high"
  "en/en_US/ljspeech/high/en_US-ljspeech-high"
  "en/en_US/joe/medium/en_US-joe-medium"
  "es/es_ES/sharvard/medium/es_ES-sharvard-medium"
  "es/es_MX/ald/medium/es_MX-ald-medium"
  "es/es_AR/daniela/high/es_AR-daniela-high"
  "es/es_MX/claude/high/es_MX-claude-high"
  "es/es_ES/davefx/medium/es_ES-davefx-medium"
)

for v in "${VOICES[@]}"; do
  name=$(basename "$v")
  if [ -s "voices/$name.onnx" ] && [ -s "voices/$name.onnx.json" ]; then
    echo "$name already present, skipping"
  else
    echo "Downloading $name..."
    curl -L --fail -o "voices/$name.onnx" "$BASE_URL/$v.onnx"
    curl -L --fail -o "voices/$name.onnx.json" "$BASE_URL/$v.onnx.json"
  fi
done

echo ""
echo "=== Setup complete ==="
echo ""
echo "To start the server, run:"
echo "  source venv/bin/activate"
echo "  python main.py"
echo ""
echo "The server will be available at:"
echo "  Local:   http://localhost:8000"
echo "  Network: http://$(ipconfig getifaddr en0 2>/dev/null || echo 'YOUR_LOCAL_IP'):8000"
echo ""
echo "Share the Network URL with your team (same WiFi required)"
