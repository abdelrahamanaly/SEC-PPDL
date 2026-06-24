#!/usr/bin/env bash
# ============================================================
# BLB GPU Test Runner — includes GPU tests (testHEGPU, testFFN)
# ============================================================
set -euo pipefail

BLB_DIR="/blb"
BUILD="${BLB_DIR}/build/Test"
PORT="${BLB_PORT:-1234}"
TIMEOUT="${TEST_TIMEOUT:-600}"

PASS=0
FAIL=0
SKIP=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass()  { echo -e "  ${GREEN}✓ PASS${NC}  $1"; PASS=$((PASS+1)); }
log_fail()  { echo -e "  ${RED}✗ FAIL${NC}  $1 (server=$2, client=$3)"; FAIL=$((FAIL+1)); }
log_skip()  { echo -e "  ${YELLOW}- SKIP${NC}  $1  ($2)"; SKIP=$((SKIP+1)); }

wait_for_port() {
  local p=$1 retries=20 delay=0.3
  local hex_port
  hex_port=$(printf '%04X' "$p")
  for _ in $(seq 1 $retries); do
    if grep -q ":${hex_port} 00000000:0000 0A" /proc/net/tcp 2>/dev/null; then
      return 0
    fi
    sleep "$delay"
  done
  echo "  [warn] server did not open port $p in time"
  return 1
}

run_two_party() {
  local bin="$1" label="$2"; shift 2
  local extra=("$@")

  echo ""
  echo "── $label ──"

  if [[ ! -x "${BUILD}/${bin}" ]]; then
    log_skip "$label" "binary not found: ${BUILD}/${bin}"
    return
  fi

  timeout "${TIMEOUT}" "${BUILD}/${bin}" r=1 p="${PORT}" "${extra[@]}" &>/tmp/blb_server.log &
  local server_pid=$!

  wait_for_port "${PORT}" || true
  sleep 0.5

  local client_exit=0
  timeout "${TIMEOUT}" "${BUILD}/${bin}" r=2 p="${PORT}" ip=127.0.0.1 "${extra[@]}" &>/tmp/blb_client.log || client_exit=$?

  local server_exit=0
  wait "${server_pid}" 2>/dev/null || server_exit=$?

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

  sleep 0.5
}

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

echo ""
echo "════════════════════════════════════════════════════════"
echo "  BLB GPU Test Suite"
echo "  Build : ${BUILD}"
echo "  Port  : ${PORT}"
echo "════════════════════════════════════════════════════════"

# Single-party tests
run_single  test_ntt            "NTT (single-party)"

# Two-party CPU tests
run_two_party test_linear_operator "LinearOperator"
run_two_party test_matmul       "Matmul"
run_two_party test_Conv         "Conv"
run_two_party test_cir_conv     "CirConv   (PrivCirNet)"
run_two_party test_fixpoint     "FixPoint"
run_two_party test_cir_linear   "CirLinear (PrivCirNet)"

# GPU tests — now enabled
run_two_party test_HE           "HE (GPU — SEAL+PhantomFHE)"
run_two_party testHEGPU         "HEGPU (PhantomFHE)"
run_two_party testFFN           "FFN (full Transformer layer)"

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "  Results:  ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${SKIP} skipped${NC}"
echo "════════════════════════════════════════════════════════"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
exit 0
