#!/usr/bin/env bash
# ============================================================
# BLB entrypoint — dispatches on CMD
# ============================================================
set -euo pipefail

CMD="${1:-test}"

case "$CMD" in
  test)
    echo "════════════════════════════════════════════════════"
    echo "  BLB — Full Test Suite (CPU + GPU)"
    echo "════════════════════════════════════════════════════"
    exec /docker-scripts/run_tests_gpu.sh
    ;;
  build)
    echo "Re-building BLB..."
    exec /docker-scripts/build_blb.sh
    ;;
  server)
    # Used in two-container mode; run_tests.sh controls which tests to serve
    exec /docker-scripts/run_server.sh
    ;;
  client)
    exec /docker-scripts/run_client.sh
    ;;
  benchmark)
    shift
    exec /docker-scripts/benchmark.sh "$@"
    ;;
  manual)
    shift
    exec /docker-scripts/run_manual.sh "$@"
    ;;
  bash|sh)
    exec /bin/bash
    ;;
  *)
    # Pass arbitrary commands through
    exec "$@"
    ;;
esac
