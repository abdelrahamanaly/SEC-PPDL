#!/usr/bin/env bash
# ============================================================
# Rebuild only BLB (assumes deps already built in image)
# ============================================================
set -euo pipefail

cd /blb
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DUSE_HE_GPU=OFF
cmake --build build -j"$(nproc)"
echo "BLB build complete."
