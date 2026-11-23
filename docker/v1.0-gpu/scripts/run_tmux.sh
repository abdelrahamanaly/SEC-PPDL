#!/usr/bin/env bash
# ============================================================
# BLB tmux Two-Container Test Runner
# ============================================================
# Runs server + client in separate Docker containers with a
# tmux split view so you can watch both sides live.
#
# Usage (from host, inside docker/v1.0/):
#   ./scripts/run_tmux.sh                    # default: test_cir_linear
#   ./scripts/run_tmux.sh test_matmul        # specific test
#   ./scripts/run_tmux.sh --list             # list available tests
#
# Prerequisites: tmux, docker compose
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SESSION="blb-test"
TEST="${1:-test_cir_linear}"
PORT="${BLB_PORT:-1234}"

ALL_TESTS=(
  test_ntt
  test_linear_operator
  test_matmul
  test_Conv
  test_cir_conv
  test_fixpoint
  test_cir_linear
)

if [[ "$TEST" == "--list" ]]; then
  echo "Available tests:"
  printf '  %s\n' "${ALL_TESTS[@]}"
  exit 0
fi

# Validate test name
VALID=false
for t in "${ALL_TESTS[@]}"; do
  [[ "$t" == "$TEST" ]] && VALID=true
done
if ! $VALID; then
  echo "Unknown test: $TEST"
  echo "Available: ${ALL_TESTS[*]}"
  exit 1
fi

cd "$COMPOSE_DIR"

# Clean up any previous run
docker compose down --remove-orphans 2>/dev/null || true

# Build image if needed
echo "Building image..."
docker compose build

# Kill existing tmux session if any
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo "Starting tmux session '$SESSION' with test: $TEST"
echo "  Server (top pane)  — ALICE (r=1)"
echo "  Client (bottom pane) — BOB (r=2)"
echo ""
echo "Attach with: tmux attach -t $SESSION"

# Create tmux session with server pane
tmux new-session -d -s "$SESSION" -n "blb" \
  "echo '=== SERVER (ALICE) === Test: $TEST'; \
   docker compose run --rm -e BLB_PORT=$PORT blb-server; \
   echo ''; echo 'Server exited. Press Enter to close.'; read"

# Split horizontally and run client
tmux split-window -t "$SESSION" -v \
  "echo '=== CLIENT (BOB) === Test: $TEST'; \
   echo 'Waiting 5s for server...'; sleep 5; \
   docker compose run --rm -e BLB_PORT=$PORT blb-client; \
   echo ''; echo 'Client exited. Press Enter to close.'; read"

# Set pane titles
tmux select-pane -t "$SESSION:0.0" -T "Server (ALICE)"
tmux select-pane -t "$SESSION:0.1" -T "Client (BOB)"

# Attach
tmux attach -t "$SESSION"

# Cleanup on exit
docker compose down --remove-orphans 2>/dev/null || true
echo "Containers cleaned up."
