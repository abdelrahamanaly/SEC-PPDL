#!/usr/bin/env bash
# ============================================================
# Two-container mode: client side
# Waits for server to be reachable, then runs the test binary.
# ============================================================
set -euo pipefail

PORT="${BLB_PORT:-1234}"
SERVER="${BLB_SERVER_IP:-blb-server}"
TEST="${TEST_NAME:-test_cir_linear}"
BIN="/blb/build/Test/${TEST}"

echo "Waiting for server at ${SERVER}:${PORT}..."
# Do NOT use nc -z — it would consume the server's single accept().
# Instead check /proc/net/tcp for LISTEN state (0A) on the port.
hex_port=$(printf '%04X' "${PORT}")
for i in $(seq 1 40); do
  if grep -q ":${hex_port} 00000000:0000 0A" /proc/net/tcp 2>/dev/null; then
    break
  fi
  sleep 0.5
done

echo "Starting client: ${TEST}  server=${SERVER}:${PORT}"
exec "${BIN}" r=2 p="${PORT}" ip="${SERVER}"
