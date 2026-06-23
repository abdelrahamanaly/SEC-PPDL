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
for i in $(seq 1 40); do
  nc -z "${SERVER}" "${PORT}" 2>/dev/null && break
  sleep 0.5
done

echo "Starting client: ${TEST}  server=${SERVER}:${PORT}"
exec "${BIN}" r=2 p="${PORT}" ip="${SERVER}"
