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

# Download voice models
echo ""
echo "Downloading voice models (this may take a few minutes)..."
mkdir -p voices

BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main"

# English voice
if [ ! -f "voices/en_US-lessac-medium.onnx" ]; then
  echo "Downloading English voice..."
  curl -L -o voices/en_US-lessac-medium.onnx \
    "$BASE_URL/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
  curl -L -o voices/en_US-lessac-medium.onnx.json \
    "$BASE_URL/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json"
  echo "English voice downloaded"
else
  echo "English voice already present, skipping"
fi

# Spanish voice
if [ ! -f "voices/es_ES-sharvard-medium.onnx" ]; then
  echo "Downloading Spanish voice..."
  curl -L -o voices/es_ES-sharvard-medium.onnx \
    "$BASE_URL/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx"
  curl -L -o voices/es_ES-sharvard-medium.onnx.json \
    "$BASE_URL/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx.json"
  echo "Spanish voice downloaded"
else
  echo "Spanish voice already present, skipping"
fi

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
