#!/bin/bash
# Start Netryx (macOS / Linux). Run ./setup.sh once first.
cd "$(dirname "$0")"
if [ ! -x venv/bin/python ]; then
    echo "Netryx isn't set up yet. Run ./setup.sh first."
    exit 1
fi
export PYTORCH_ENABLE_MPS_FALLBACK=1
exec venv/bin/python test_super.py
