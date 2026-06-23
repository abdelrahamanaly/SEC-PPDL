#!/usr/bin/env bash
# ============================================================
# ASAN/UBSAN rebuild and test — runs inside the container
# ============================================================
set -euo pipefail

echo "Rebuilding BLB with ASAN+UBSAN..."
cd /blb
rm -rf build
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Debug \
  -DUSE_HE_GPU=OFF \
  "-DCMAKE_CXX_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer" \
  "-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address,undefined" 2>&1 | tail -5
cmake --build build -j"$(nproc)" 2>&1 | tail -10
echo ""
echo "BUILD_DONE"

export ASAN_OPTIONS=detect_leaks=0
export UBSAN_OPTIONS=print_stacktrace=1

PORT=5555

echo ""
echo "--- ASAN: test_ntt ---"
/blb/build/Test/test_ntt 2>&1
echo "NTT_EXIT=$?"

wait_for_port() {
  local p=$1
  local hex
  hex=$(printf '%04X' "$p")
  for _ in $(seq 1 30); do
    grep -q ":${hex} 00000000:0000 0A" /proc/net/tcp 2>/dev/null && return 0
    sleep 0.3
  done
  return 1
}

echo ""
echo "--- ASAN: test_linear_operator ---"
/blb/build/Test/test_linear_operator r=1 p=$PORT &>/tmp/asan_s.log &
SPID=$!
wait_for_port $PORT || true
sleep 0.3
timeout 300 /blb/build/Test/test_linear_operator r=2 p=$PORT ip=127.0.0.1 2>&1 | tail -15
CE=$?
wait $SPID 2>/dev/null || true
SE=$?
echo "LO_EXIT server=$SE client=$CE"
grep -i -E "error|sanitize|ubsan|asan" /tmp/asan_s.log 2>/dev/null || echo "NO_SANITIZER_ERRORS_LO"

PORT=5556
echo ""
echo "--- ASAN: test_fixpoint ---"
/blb/build/Test/test_fixpoint r=1 p=$PORT &>/tmp/asan_s2.log &
SPID=$!
wait_for_port $PORT || true
sleep 0.3
timeout 300 /blb/build/Test/test_fixpoint r=2 p=$PORT ip=127.0.0.1 2>&1 | tail -15
CE=$?
wait $SPID 2>/dev/null || true
SE=$?
echo "FP_EXIT server=$SE client=$CE"
grep -i -E "error|sanitize|ubsan|asan" /tmp/asan_s2.log 2>/dev/null || echo "NO_SANITIZER_ERRORS_FP"

PORT=5557
echo ""
echo "--- ASAN: test_matmul ---"
/blb/build/Test/test_matmul r=1 p=$PORT &>/tmp/asan_s3.log &
SPID=$!
wait_for_port $PORT || true
sleep 0.3
timeout 300 /blb/build/Test/test_matmul r=2 p=$PORT ip=127.0.0.1 2>&1 | tail -15
CE=$?
wait $SPID 2>/dev/null || true
SE=$?
echo "MM_EXIT server=$SE client=$CE"
grep -i -E "error|sanitize|ubsan|asan" /tmp/asan_s3.log 2>/dev/null || echo "NO_SANITIZER_ERRORS_MM"

echo ""
echo "ASAN_ALL_DONE"
