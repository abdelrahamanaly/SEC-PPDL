#!/usr/bin/env bash
# ============================================================
# BLB Benchmark Runner — runs a test N times and emits JSON
# ============================================================
set -euo pipefail

BLB_DIR="/blb"
BUILD="${BLB_DIR}/build/Test"
PORT="${BLB_PORT:-1234}"
RESULTS_DIR="${BLB_DIR}/results"

SINGLE_PARTY_TESTS="test_ntt"

usage() {
  echo "Usage: benchmark.sh --test <binary> [--runs N] [--port P] [--output path.json]"
  exit 1
}

TEST=""
RUNS=5
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test)   TEST="$2"; shift 2 ;;
    --runs)   RUNS="$2"; shift 2 ;;
    --port)   PORT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *)        usage ;;
  esac
done

[[ -z "$TEST" ]] && usage

BINARY="${BUILD}/${TEST}"
if [[ ! -x "$BINARY" ]]; then
  echo "ERROR: binary not found or not executable: ${BINARY}" >&2
  exit 1
fi

[[ -z "$OUTPUT" ]] && OUTPUT="${RESULTS_DIR}/${TEST}.json"
mkdir -p "$(dirname "$OUTPUT")"

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
  return 1
}

echo "Benchmarking: ${TEST}"
echo "  Runs: ${RUNS}, Port: ${PORT}"
echo "  Output: ${OUTPUT}"
echo ""

IS_SINGLE=false
for sp in $SINGLE_PARTY_TESTS; do
  [[ "$TEST" == "$sp" ]] && IS_SINGLE=true
done

TIMES=()
COMM_SENT=0
COMM_RECV=0

for ((i=1; i<=RUNS; i++)); do
  echo "  Run ${i}/${RUNS}..."

  START_NS=$(date +%s%N)

  if [[ "$IS_SINGLE" == "true" ]]; then
    "${BINARY}" &>/tmp/bench_server.log
    RUN_EXIT=$?
    END_NS=$(date +%s%N)
    if [[ ${RUN_EXIT} -ne 0 ]]; then
      echo "  FAILED (exit=${RUN_EXIT})"
      tail -10 /tmp/bench_server.log
      exit 1
    fi
  else
    # Server (ALICE)
    "${BINARY}" r=1 p="${PORT}" &>/tmp/bench_server.log &
    SERVER_PID=$!

    wait_for_port "${PORT}" || { echo "  Server did not start"; kill $SERVER_PID 2>/dev/null; exit 1; }
    sleep 0.3

    # Client (BOB)
    local_client_exit=0
    "${BINARY}" r=2 p="${PORT}" ip=127.0.0.1 &>/tmp/bench_client.log || local_client_exit=$?

    local_server_exit=0
    wait "${SERVER_PID}" 2>/dev/null || local_server_exit=$?

    END_NS=$(date +%s%N)

    if [[ ${local_client_exit} -ne 0 || ${local_server_exit} -ne 0 ]]; then
      echo "  FAILED (server=${local_server_exit}, client=${local_client_exit})"
      echo "  --- server ---"
      tail -10 /tmp/bench_server.log
      echo "  --- client ---"
      tail -10 /tmp/bench_client.log
      exit 1
    fi

    if [[ $i -eq $RUNS ]]; then
      COMM_SENT=$(grep -oP 'total data sent till now = \K[0-9]+' /tmp/bench_server.log | tail -1 || echo "0")
      COMM_RECV=$(grep -oP 'total data sent till now = \K[0-9]+' /tmp/bench_client.log | tail -1 || echo "0")
    fi
  fi

  ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
  TIMES+=("$ELAPSED_MS")
  echo "    ${ELAPSED_MS} ms"

  sleep 0.5
done

# Compute stats and write JSON using python3 (available in the image, unlike bc)
VALUES_JSON=$(printf '%s\n' "${TIMES[@]}" | paste -sd, -)

python3 -c "
import json, math
vals = [${VALUES_JSON}]
n = len(vals)
mean = sum(vals) / n
std = math.sqrt(sum((v - mean)**2 for v in vals) / n) if n > 1 else 0.0
data = {
    'test': '${TEST}',
    'runs': ${RUNS},
    'wall_time_ms': {'mean': round(mean, 2), 'std': round(std, 2), 'values': vals},
    'comm_bytes': {'server_sent': ${COMM_SENT:-0}, 'client_sent': ${COMM_RECV:-0}}
}
with open('${OUTPUT}', 'w') as f:
    json.dump(data, f, indent=2)
print()
print(f'  Mean: {mean:.2f} ms (std: {std:.2f})')
print(f'  Comm: server_sent=${COMM_SENT:-0} B, client_sent=${COMM_RECV:-0} B')
print(f'  Saved: ${OUTPUT}')
"
