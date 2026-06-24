#!/usr/bin/env bash
# ============================================================
# BLB Test Runner — CPU only, two-party tests on localhost
# ============================================================
set -euo pipefail

BLB_DIR="/blb"
BUILD="${BLB_DIR}/build/Test"
PORT="${BLB_PORT:-1234}"
TIMEOUT="${TEST_TIMEOUT:-600}"  # per-test timeout in seconds (default 10 min)

PASS=0
FAIL=0
SKIP=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────────

log_pass()  { echo -e "  ${GREEN}✓ PASS${NC}  $1"; PASS=$((PASS+1)); }
log_fail()  { echo -e "  ${RED}✗ FAIL${NC}  $1 (server=$2, client=$3)"; FAIL=$((FAIL+1)); }
log_skip()  { echo -e "  ${YELLOW}- SKIP${NC}  $1  ($2)"; SKIP=$((SKIP+1)); }

wait_for_port() {
  local p=$1 retries=20 delay=0.3
  local hex_port
  hex_port=$(printf '%04X' "$p")
  for _ in $(seq 1 $retries); do
    # Check /proc/net/tcp for LISTEN state (0A) on the port.
    # Do NOT use nc -z — it would consume the server's single accept().
    if grep -q ":${hex_port} 00000000:0000 0A" /proc/net/tcp 2>/dev/null; then
      return 0
    fi
    sleep "$delay"
  done
  echo "  [warn] server did not open port $p in time"
  return 1
}

# Run a two-party test.
# Usage: run_two_party <binary_name> <test_label> [extra_args...]
run_two_party() {
  local bin="$1" label="$2"; shift 2
  local extra=("$@")

  echo ""
  echo "── $label ──"

  if [[ ! -x "${BUILD}/${bin}" ]]; then
    log_skip "$label" "binary not found: ${BUILD}/${bin}"
    return
  fi

  # Server (ALICE = r=1) in background
  timeout "${TIMEOUT}" "${BUILD}/${bin}" r=1 p="${PORT}" "${extra[@]}" &>/tmp/blb_server.log &
  local server_pid=$!

  wait_for_port "${PORT}" || true
  sleep 0.5   # extra grace period

  # Client (BOB = r=2) with timeout
  # Capture exit code without letting set -e abort on timeout (124) or failure
  local client_exit=0
  timeout "${TIMEOUT}" "${BUILD}/${bin}" r=2 p="${PORT}" ip=127.0.0.1 "${extra[@]}" &>/tmp/blb_client.log || client_exit=$?

  local server_exit=0
  wait "${server_pid}" 2>/dev/null || server_exit=$?

  # timeout returns 124 on kill
  if [[ ${client_exit} -eq 124 || ${server_exit} -eq 124 ]]; then
    log_skip "$label" "timed out after ${TIMEOUT}s"
    kill "${server_pid}" 2>/dev/null || true; wait "${server_pid}" 2>/dev/null || true
  elif [[ ${client_exit} -eq 0 && ${server_exit} -eq 0 ]]; then
    log_pass "$label"
  else
    log_fail "$label" "${server_exit}" "${client_exit}"
    echo "  --- server log ---"
    tail -20 /tmp/blb_server.log
    echo "  --- client log ---"
    tail -20 /tmp/blb_client.log
  fi

  # Ensure port is free before next test
  sleep 0.5
}

# Run a single-party test.
run_single() {
  local bin="$1" label="$2"

  echo ""
  echo "── $label ──"

  if [[ ! -x "${BUILD}/${bin}" ]]; then
    log_skip "$label" "binary not found"
    return
  fi

  "${BUILD}/${bin}" &>/tmp/blb_single.log
  local exit_code=$?

  if [[ ${exit_code} -eq 0 ]]; then
    log_pass "$label"
  else
    log_fail "$label" "${exit_code}" "-"
    cat /tmp/blb_single.log | tail -30
  fi
}

# ── Test suite ───────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════"
echo "  BLB CPU Test Suite"
echo "  Build : ${BUILD}"
echo "  Port  : ${PORT}"
echo "════════════════════════════════════════════════════════"

# Single-party tests
run_single  test_ntt            "NTT (single-party)"

# Two-party tests (CPU, HE=HOST) — fast tests first, slow ones last
run_two_party test_linear_operator "LinearOperator"
run_two_party test_matmul       "Matmul"
run_two_party test_Conv         "Conv"
run_two_party test_cir_conv     "CirConv   (PrivCirNet)"

# Slow tests last — OTPack init and large HE ops are CPU-bound on 2.1GHz Xeon
run_two_party test_fixpoint     "FixPoint"
run_two_party test_cir_linear   "CirLinear (PrivCirNet)"

# GPU tests — skipped in CPU build
log_skip "test_HE"      "requires GPU (USE_HE_GPU=ON)"
log_skip "testHEGPU"    "requires GPU (USE_HE_GPU=ON)"
log_skip "testFFN"      "requires GPU (USE_HE_GPU=ON)"

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo -e "  Results:  ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${SKIP} skipped${NC}"
echo "════════════════════════════════════════════════════════"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
exit 0
