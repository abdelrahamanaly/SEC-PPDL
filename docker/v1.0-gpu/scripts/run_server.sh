#!/usr/bin/env bash
# ============================================================
# Two-container mode: server side
# Reads TEST_NAME from env to know which binary to serve.
# ============================================================
set -euo pipefail

PORT="${BLB_PORT:-1234}"
TEST="${TEST_NAME:-test_cir_linear}"
BIN="/blb/build/Test/${TEST}"

echo "Starting server: ${TEST}  port=${PORT}"
exec "${BIN}" r=1 p="${PORT}"
