#!/usr/bin/env bash
# ============================================================
# BLB Manual Test Runner — single container, interactive
# ============================================================
# Usage (from inside the container):
#   run_manual.sh                      # run all CPU tests
#   run_manual.sh --test test_matmul   # run one test
#   run_manual.sh --list               # list available tests
#
# From host via docker compose:
#   docker compose run blb manual
#   docker compose run blb manual --test test_matmul
# ============================================================
set -euo pipefail

BUILD="/blb/build/Test"
PORT="${BLB_PORT:-1234}"

# All CPU tests in recommended order (fast first)
ALL_CPU_TESTS=(
  "test_ntt:single"
  "test_linear_operator:two_party"
  "test_matmul:two_party"
  "test_Conv:two_party"
  "test_cir_conv:two_party"
  "test_fixpoint:two_party"
  "test_cir_linear:two_party"
)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

list_tests() {
  echo ""
  echo -e "${CYAN}Available CPU tests:${NC}"
  echo ""
  for entry in "${ALL_CPU_TESTS[@]}"; do
    local name="${entry%%:*}"
    local kind="${entry##*:}"
    local exists="✓"
    [[ ! -x "${BUILD}/${name}" ]] && exists="✗"
    printf "  %s %-25s (%s)\n" "$exists" "$name" "$kind"
  done
  echo ""
  echo "Usage: run_manual.sh --test <name>   # run one test"
  echo "       run_manual.sh                 # run all"
}

run_single_party() {
  local bin="$1"
  echo -e "\n${CYAN}── ${bin} (single-party) ──${NC}"
  if [[ ! -x "${BUILD}/${bin}" ]]; then
    echo -e "  ${RED}Binary not found: ${BUILD}/${bin}${NC}"
    return 1
  fi
  "${BUILD}/${bin}"
  echo -e "  ${GREEN}✓ Done${NC}"
}

run_two_party() {
  local bin="$1"
  echo -e "\n${CYAN}── ${bin} (two-party on localhost:${PORT}) ──${NC}"
  if [[ ! -x "${BUILD}/${bin}" ]]; then
    echo -e "  ${RED}Binary not found: ${BUILD}/${bin}${NC}"
    return 1
  fi

  echo "  Starting server (r=1)..."
  "${BUILD}/${bin}" r=1 p="${PORT}" &
  local server_pid=$!

  # Wait for server port (check /proc/net/tcp, not nc -z which steals the accept)
  local hex_port
  hex_port=$(printf '%04X' "${PORT}")
  for _ in $(seq 1 30); do
    grep -q ":${hex_port} 00000000:0000 0A" /proc/net/tcp 2>/dev/null && break
    sleep 0.3
  done
  sleep 0.5

  echo "  Starting client (r=2)..."
  local client_exit=0
  "${BUILD}/${bin}" r=2 p="${PORT}" ip=127.0.0.1 || client_exit=$?

  local server_exit=0
  wait "${server_pid}" 2>/dev/null || server_exit=$?

  echo ""
  if [[ ${client_exit} -eq 0 && ${server_exit} -eq 0 ]]; then
    echo -e "  ${GREEN}✓ PASS${NC} (server=0, client=0)"
  else
    echo -e "  ${RED}✗ FAIL${NC} (server=${server_exit}, client=${client_exit})"
  fi
  sleep 0.5
}

run_test() {
  local name="$1"
  local kind=""
  for entry in "${ALL_CPU_TESTS[@]}"; do
    if [[ "${entry%%:*}" == "$name" ]]; then
      kind="${entry##*:}"
      break
    fi
  done
  if [[ -z "$kind" ]]; then
    echo -e "${RED}Unknown test: ${name}${NC}"
    list_tests
    return 1
  fi
  if [[ "$kind" == "single" ]]; then
    run_single_party "$name"
  else
    run_two_party "$name"
  fi
}

# ── Parse args ──
TEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --test)  TEST="$2"; shift 2 ;;
    --list)  list_tests; exit 0 ;;
    *)       echo "Unknown arg: $1"; list_tests; exit 1 ;;
  esac
done

if [[ -n "$TEST" ]]; then
  run_test "$TEST"
else
  echo -e "${CYAN}════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  BLB Manual Test Runner — All CPU Tests${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════${NC}"
  for entry in "${ALL_CPU_TESTS[@]}"; do
    run_test "${entry%%:*}"
  done
  echo -e "\n${GREEN}All tests complete.${NC}"
fi
