#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Netryx Astra V2 — one-command setup for macOS and Linux
# Run:  chmod +x setup.sh && ./setup.sh
# Safe to run again: finished steps are skipped.
# ═══════════════════════════════════════════════════════════════
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
LOG="$SCRIPT_DIR/installer.log"
: > "$LOG"
OS="$(uname)"

echo ""
echo "🔱 Netryx Astra V2 — Setup"
echo "═══════════════════════════════════════"
echo ""

# ── Python 3.10–3.12 with Tk (the app's window needs Tk) ──────────
python_ok() {   # $1 = python executable; succeeds if 3.10–3.12 and Tk works
    "$1" -c "import sys, tkinter; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,12) else 1)" >/dev/null 2>&1
}
python_version_ok() {
    "$1" -c "import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,12) else 1)" >/dev/null 2>&1
}

PY=""
NO_TK=""
for cand in python3.12 python3.11 python3.10 python3 \
            /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/3.10/bin/python3; do
    path="$(command -v "$cand" 2>/dev/null || true)"
    [ -z "$path" ] && continue
    if python_ok "$path"; then PY="$path"; break; fi
    if python_version_ok "$path"; then NO_TK="$path"; fi
done

if [ -z "$PY" ]; then
    echo "[ERROR] Netryx needs Python 3.10, 3.11 or 3.12 with Tk (for its window)."
    if [ -n "$NO_TK" ]; then
        echo "        Found $NO_TK, but it was installed without Tk."
    fi
    if [ "$OS" = "Darwin" ]; then
        echo "        Easiest fix: install Python 3.12 from https://www.python.org/downloads/macos/"
        echo "        (it includes Tk). With Homebrew instead: brew install python@3.12 python-tk@3.12"
    else
        echo "        Install Python 3.12 and Tk, e.g. on Ubuntu/Debian:"
        echo "        sudo apt install python3.12 python3.12-venv python3-tk"
    fi
    echo "        Then run ./setup.sh again."
    exit 1
fi
echo "[OK] Using $("$PY" --version) at $PY"

if ! command -v git &> /dev/null; then
    echo "[ERROR] Git not found."
    if [ "$OS" = "Darwin" ]; then
        echo "        Install it with: xcode-select --install"
    else
        echo "        Install it with your package manager, e.g. sudo apt install git"
    fi
    exit 1
fi
echo "[OK] Git found"

HAS_NVIDIA=""
if [ "$OS" = "Linux" ] && command -v nvidia-smi &> /dev/null; then
    HAS_NVIDIA=1
    echo "[OK] NVIDIA GPU detected"
    command -v nvcc &> /dev/null || echo "[INFO] CUDA Toolkit (nvcc) not found: MASt3R will use a slower fallback. Optional."
fi

# ── Virtual environment (rebuilt if it was made with an unsuitable Python) ──
if [ -d venv ] && ! python_ok venv/bin/python; then
    echo "[SETUP] Existing venv uses an unsuitable Python; recreating it..."
    rm -rf venv
fi
if [ ! -d venv ]; then
    echo "[SETUP] Creating virtual environment..."
    "$PY" -m venv venv
fi
# shellcheck disable=SC1091
source venv/bin/activate
echo "[OK] Virtual environment ready"

# ── PyTorch ───────────────────────────────────────────────────────
echo "[SETUP] Installing PyTorch (this can take a few minutes)..."
python -m pip install --upgrade pip -q
if [ -n "$HAS_NVIDIA" ]; then
    python -m pip install -q torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cu124
else
    python -m pip install -q torch==2.6.0 torchvision==0.21.0   # includes Apple GPU (MPS) support on Macs
fi

echo "[SETUP] Installing Python dependencies..."
python -m pip install -q -r requirements.txt
if [ -n "$HAS_NVIDIA" ]; then
    python -m pip install -q --upgrade triton >>"$LOG" 2>&1 || echo "[INFO] triton not installed (optional)."
fi
echo "[OK] Dependencies installed"

# ── MASt3R (cloned next to this folder) ───────────────────────────
MAST3R_DIR="$SCRIPT_DIR/../mast3r"
if [ -f "$MAST3R_DIR/mast3r/model.py" ]; then
    echo "[OK] MASt3R already present at $(cd "$MAST3R_DIR" && pwd)"
else
    echo "[SETUP] Downloading MASt3R..."
    git clone --recursive https://github.com/naver/mast3r.git "$MAST3R_DIR"
fi
python -m pip install -q -r "$MAST3R_DIR/requirements.txt"
python -m pip install -q -r "$MAST3R_DIR/dust3r/requirements.txt"
echo "[OK] MASt3R ready"

# ── Model weights (optional here: the app downloads them on first use) ──
echo "[SETUP] Downloading MegaLoc model weights (first time only)..."
if python -c "import torch; torch.hub.load('gmberton/MegaLoc', 'get_trained_model', trust_repo=True)" >>"$LOG" 2>&1; then
    echo "[OK] MegaLoc ready"
else
    echo "[WARN] MegaLoc download failed; the app will retry on first run (details in installer.log)"
fi

echo "[SETUP] Downloading MASt3R model weights (~1.2 GB, first time only)..."
if python -c "import sys,os; p=os.path.abspath('$MAST3R_DIR'); sys.path[:0]=[p, os.path.join(p,'dust3r'), os.path.join(p,'dust3r','croco')]; from mast3r.model import AsymmetricMASt3R; AsymmetricMASt3R.from_pretrained('naver/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric')" >>"$LOG" 2>&1; then
    echo "[OK] MASt3R weights ready"
else
    echo "[WARN] MASt3R weights download failed; the app will retry on first run (details in installer.log)"
fi

HUB_DIR="$HOME/.cache/torch/hub/gmberton_VPR-methods-evaluation_master"
if [ -d "$HUB_DIR" ]; then
    echo "[OK] MixVPR code already present"
else
    mkdir -p "$(dirname "$HUB_DIR")"
    if git clone -q https://github.com/gmberton/VPR-methods-evaluation.git "$HUB_DIR" >>"$LOG" 2>&1; then
        echo "[OK] MixVPR installed"
    else
        echo "[WARN] MixVPR download failed (only needed for the MixVPR encoder)"
    fi
fi

mkdir -p netryx_data/megaloc_parts netryx_data/indexes

# ── Launchers ─────────────────────────────────────────────────────
chmod +x run.sh 2>/dev/null || true
if [ "$OS" = "Darwin" ]; then
    cat > Netryx.command <<EOF
#!/bin/bash
# Double-click to start Netryx
cd "\$(dirname "\$0")" && ./run.sh
EOF
    chmod +x Netryx.command
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "  Setup complete!"
echo ""
echo "  To start Netryx:"
if [ "$OS" = "Darwin" ]; then
    echo "    double-click Netryx.command in this folder, or"
fi
echo "    run ./run.sh"
echo "════════════════════════════════════════════════════"
