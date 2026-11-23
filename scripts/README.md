# BLB Scripts Reference

Detailed documentation for every build, test, benchmark, and validation script in the BLB framework.

All scripts run **inside Docker containers** unless explicitly marked as host-side.
No script modifies the host machine — the only host-side operations are invoking Docker commands and tmux.

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Architecture](#architecture)
3. [Container-Internal Scripts](#container-internal-scripts)
   - [entrypoint.sh](#entrypointsh)
   - [run_tests.sh](#run_testssh)
   - [run_tests_gpu.sh](#run_tests_gpush)
   - [run_manual.sh](#run_manualsh)
   - [benchmark.sh](#benchmarksh)
   - [run_asan.sh](#run_asansh)
   - [cross_validate.sh](#cross_validatesh)
   - [gen_report_table.py](#gen_report_tablepy)
   - [build_blb.sh](#build_blbsh)
   - [run_server.sh](#run_serversh)
   - [run_client.sh](#run_clientsh)
4. [Host-Side Scripts](#host-side-scripts)
   - [run_tmux.sh](#run_tmuxsh)
5. [Utility Scripts](#utility-scripts)
   - [throttle.sh](#throttlesh)
6. [Environment Variables](#environment-variables)
7. [Port Detection: Why Not nc -z](#port-detection-why-not-nc--z)
8. [Adding a New Script](#adding-a-new-script)

---

## Quick Reference

| Script | Location | Runs Where | Purpose |
|--------|----------|------------|---------|
| `entrypoint.sh` | `docker/v1.0/scripts/` | Container | Docker entrypoint — routes commands to scripts |
| `run_tests.sh` | `docker/v1.0/scripts/` | Container | Full CPU test suite (7 tests) |
| `run_tests_gpu.sh` | `docker/v1.0-gpu/scripts/` | Container | Full CPU+GPU test suite (10 tests) |
| `run_manual.sh` | `docker/v1.0/scripts/` | Container | Interactive single-test selector |
| `benchmark.sh` | `docker/v1.0/scripts/` | Container | Run test N times, emit JSON stats |
| `run_asan.sh` | `docker/v1.0/scripts/` | Container | ASAN/UBSAN instrumented rebuild + test |
| `cross_validate.sh` | `docker/v1.0/scripts/` | Container | C++ output vs Python reference validation |
| `gen_report_table.py` | `docker/v1.0/scripts/` | Container | Read JSON results, emit LaTeX table |
| `build_blb.sh` | `docker/v1.0/scripts/` | Container | Quick BLB-only rebuild (deps cached) |
| `run_server.sh` | `docker/v1.0/scripts/` | Container | Two-container mode: server (ALICE) |
| `run_client.sh` | `docker/v1.0/scripts/` | Container | Two-container mode: client (BOB) |
| `run_tmux.sh` | `docker/v1.0/scripts/` | **Host** | tmux split-view two-container launcher |
| `throttle.sh` | repo root | **Host** | Network throttling via `tc` (emp-toolkit) |

---

## Architecture

```
Host Machine
  |
  +-- docker compose up          # builds image, runs entrypoint.sh test
  +-- docker compose run blb ... # runs entrypoint.sh with custom CMD
  |
  +-- Docker Container (blb:v1.0)
        |
        /docker-scripts/              <-- copied from docker/v1.0/scripts/ at build time
        |  entrypoint.sh              <-- ENTRYPOINT, dispatches CMD
        |  run_tests.sh               <-- "test" command
        |  run_manual.sh              <-- "manual" command
        |  benchmark.sh               <-- "benchmark" command
        |  build_blb.sh               <-- "build" command
        |  run_server.sh              <-- "server" command
        |  run_client.sh              <-- "client" command
        |  run_asan.sh                <-- standalone (--entrypoint override)
        |  cross_validate.sh          <-- standalone (--entrypoint override)
        |  gen_report_table.py        <-- called manually or from benchmark
        |
        /blb/                         <-- full BLB source tree
           build/Test/                <-- compiled test binaries
              test_ntt
              test_linear_operator
              test_matmul
              test_Conv
              test_cir_conv
              test_fixpoint
              test_cir_linear
              test_HE          (GPU only)
              testHEGPU        (GPU only)
              testFFN          (GPU only)
           results/                   <-- benchmark JSON output
```

The Dockerfile's `COPY . .` brings the entire repo into `/blb/`. Then
`RUN cp -r docker/v1.0/scripts /docker-scripts` places scripts at a fixed path that doesn't
depend on the repo layout. The `ENTRYPOINT` is set to `/docker-scripts/entrypoint.sh`.

---

## Container-Internal Scripts

These scripts run inside the Docker container. They are copied into `/docker-scripts/` during
the Docker image build. You do not run them directly on the host.

### entrypoint.sh

**Location**: `docker/v1.0/scripts/entrypoint.sh`
**Purpose**: Docker ENTRYPOINT dispatcher. Routes the first argument (CMD) to the appropriate script.

**Supported commands**:

| CMD | What it does |
|-----|-------------|
| `test` (default) | Runs the full test suite via `run_tests.sh` |
| `build` | Rebuilds BLB from source via `build_blb.sh` |
| `server` | Starts the server role via `run_server.sh` |
| `client` | Starts the client role via `run_client.sh` |
| `benchmark` | Runs benchmarks via `benchmark.sh` (passes remaining args through) |
| `manual` | Interactive test selector via `run_manual.sh` (passes remaining args through) |
| `bash` or `sh` | Drops to an interactive shell |
| anything else | Passed through to `exec "$@"` |

**Examples from the host**:

```bash
cd docker/v1.0

# Run full test suite (default CMD = "test")
docker compose up --build

# Interactive shell inside the container
docker compose run --rm blb bash

# Run a specific benchmark
docker compose run --rm blb benchmark --test test_matmul --runs 5

# Select and run one test interactively
docker compose run --rm blb manual --test test_fixpoint
```

**GPU variant**: `docker/v1.0-gpu/scripts/entrypoint.sh` is identical except the `test`
command calls `run_tests_gpu.sh` instead of `run_tests.sh`.

---

### run_tests.sh

**Location**: `docker/v1.0/scripts/run_tests.sh`
**Purpose**: Executes the full CPU test suite in a single container. Both server (ALICE, r=1) and client (BOB, r=2) run on localhost within the same container.

**Test execution order** (fast first, slow last):

| Order | Test | Type | Typical Time |
|-------|------|------|-------------|
| 1 | `test_ntt` | single-party | ~11 ms |
| 2 | `test_linear_operator` | two-party | ~1.6 s |
| 3 | `test_matmul` | two-party | ~1.9 s |
| 4 | `test_Conv` | two-party | ~8.9 s |
| 5 | `test_cir_conv` | two-party | ~2.6 s |
| 6 | `test_fixpoint` | two-party | ~1.3 s |
| 7 | `test_cir_linear` | two-party | ~7.6 s |
| 8-10 | test_HE, testHEGPU, testFFN | two-party | SKIPPED (GPU) |

**How two-party tests work**:

1. Server binary starts in background: `test_binary r=1 p=PORT`
2. Script waits for the server to open a TCP LISTEN socket by polling `/proc/net/tcp`
3. Client binary starts in foreground: `test_binary r=2 p=PORT ip=127.0.0.1`
4. Script captures both exit codes (using `set -e`-safe pattern)
5. Both exit 0 = PASS, either non-zero = FAIL, exit 124 = TIMEOUT (skipped)

**Environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `BLB_PORT` | `1234` | TCP port for two-party protocol |
| `TEST_TIMEOUT` | `600` | Per-test timeout in seconds |

**Exit codes**:
- `0`: all tests passed (skips don't count as failures)
- `1`: at least one test failed

**Output format**:

```
════════════════════════════════════════════════════════
  BLB CPU Test Suite
  Build : /blb/build/Test
  Port  : 1234
════════════════════════════════════════════════════════

── NTT (single-party) ──
  ✓ PASS  NTT (single-party)

── LinearOperator ──
  ✓ PASS  LinearOperator

...

════════════════════════════════════════════════════════
  Results:  7 passed  0 failed  3 skipped
════════════════════════════════════════════════════════
```

---

### run_tests_gpu.sh

**Location**: `docker/v1.0-gpu/scripts/run_tests_gpu.sh`
**Purpose**: Same as `run_tests.sh` but additionally enables the three GPU tests: `test_HE`, `testHEGPU`, `testFFN`. Used only in the `blb:v1.0-gpu` image.

**Differences from CPU version**:
- GPU tests are run (not skipped)
- Header says "BLB GPU Test Suite"
- Requires NVIDIA GPU with CUDA >= 12.2 and `nvidia-container-toolkit`

---

### run_manual.sh

**Location**: `docker/v1.0/scripts/run_manual.sh`
**Purpose**: Interactive test selector. Run one test, all tests, or list available tests. Useful for debugging a single test without running the full suite.

**Usage**:

```bash
# From inside the container:
run_manual.sh                         # run all CPU tests
run_manual.sh --test test_matmul      # run one specific test
run_manual.sh --list                  # list available tests with status

# From the host via Docker Compose:
docker compose run --rm blb manual
docker compose run --rm blb manual --test test_matmul
docker compose run --rm blb manual --list
```

**Arguments**:

| Argument | Description |
|----------|-------------|
| (none) | Run all 7 CPU tests in order |
| `--test NAME` | Run a single test by binary name |
| `--list` | Print available tests with binary existence check |

**Test registry** (hardcoded in the script):

```
test_ntt              (single)
test_linear_operator  (two_party)
test_matmul           (two_party)
test_Conv             (two_party)
test_cir_conv         (two_party)
test_fixpoint         (two_party)
test_cir_linear       (two_party)
```

**Differences from run_tests.sh**:
- No timeout wrapper (tests run to completion or Ctrl-C)
- Output is not redirected to log files — stdout/stderr go directly to the terminal
- No colored summary counters — just per-test PASS/FAIL
- Designed for interactive use, not CI

---

### benchmark.sh

**Location**: `docker/v1.0/scripts/benchmark.sh`
**Purpose**: Runs a single test binary N times, measures wall-clock time for each run, extracts communication bytes from the last run's output, computes mean and standard deviation, and writes a structured JSON file.

**Usage**:

```bash
# From inside the container:
benchmark.sh --test test_matmul --runs 5 --port 4321 --output /tmp/matmul.json

# From the host via Docker Compose:
docker compose run --rm blb benchmark --test test_matmul --runs 5
docker compose run --rm blb benchmark --test test_ntt --runs 10
```

**Arguments**:

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--test NAME` | Yes | — | Test binary name (must exist in `/blb/build/Test/`) |
| `--runs N` | No | `5` | Number of repetitions |
| `--port P` | No | `$BLB_PORT` or `1234` | TCP port for two-party protocol |
| `--output PATH` | No | `/blb/results/NAME.json` | Output JSON file path |

**Single-party detection**: Tests listed in `SINGLE_PARTY_TESTS="test_ntt"` are run without
the server/client pattern. The script detects this and runs the binary directly.

**Timing method**: Uses `date +%s%N` (nanosecond precision) before and after each run.
Reports milliseconds. This measures total wall-clock time including:
- SEAL key generation (client generates secret, public, relin, Galois keys)
- Key transfer from client to server via NetIO
- The actual HE/MPC computation
- Process startup/shutdown overhead

**Statistics**: Computed via inline python3 (not `bc`, which is not in the container image):
- Mean: arithmetic mean of all run times
- Std: population standard deviation (divides by N, not N-1)

**Communication bytes**: Extracted from the last run's server and client logs by grepping
for `total data sent till now = <number>`. Only some tests print this line. If not found,
defaults to 0.

**Output JSON format**:

```json
{
  "test": "test_matmul",
  "runs": 5,
  "wall_time_ms": {
    "mean": 1911.0,
    "std": 44.1,
    "values": [1920, 1905, 1911, 1899, 1920]
  },
  "comm_bytes": {
    "server_sent": 0,
    "client_sent": 0
  }
}
```

**Exit codes**:
- `0`: all runs succeeded
- `1`: binary not found, or any run failed (server or client exit non-zero)

---

### run_asan.sh

**Location**: `docker/v1.0/scripts/run_asan.sh`
**Purpose**: Rebuilds the entire BLB codebase from scratch with AddressSanitizer (ASAN) and
UndefinedBehaviorSanitizer (UBSAN) instrumentation, then runs a subset of tests to check
for memory errors and undefined behavior.

**What it detects**:
- Heap/stack buffer overflows
- Use-after-free
- Double-free
- Memory leaks (disabled — see below)
- Signed integer overflow
- Null pointer dereference
- Misaligned memory access
- Shift out of bounds

**How to run**:

```bash
# Must bypass the default entrypoint (which expects "test", "benchmark", etc.)
docker run --name blb_asan --entrypoint /docker-scripts/run_asan.sh blb:v1.0

# View logs
docker logs blb_asan

# Clean up
docker rm blb_asan
```

You cannot use `docker compose run --rm blb` for this because entrypoint.sh doesn't have
an ASAN command. You must override the entrypoint.

**Build flags**:

```
CMAKE_BUILD_TYPE=Debug
CMAKE_CXX_FLAGS=-fsanitize=address,undefined -fno-omit-frame-pointer
CMAKE_EXE_LINKER_FLAGS=-fsanitize=address,undefined
```

**Runtime environment**:

| Variable | Value | Why |
|----------|-------|-----|
| `ASAN_OPTIONS` | `detect_leaks=0` | SEAL's static allocations trigger false-positive leak reports at process exit |
| `UBSAN_OPTIONS` | `print_stacktrace=1` | Get full stack traces on undefined behavior |

**Tests run** (each on a different port to avoid conflicts):

| Test | Port | Type |
|------|------|------|
| `test_ntt` | N/A | single-party |
| `test_linear_operator` | 5555 | two-party |
| `test_fixpoint` | 5556 | two-party |
| `test_matmul` | 5557 | two-party |

**Why only 4 tests**: The remaining tests (test_Conv, test_cir_conv, test_cir_linear) involve
larger HE operations that are very slow under ASAN instrumentation (2-10x slowdown). The 4
selected tests cover all code paths: NTT (HEXL), HE element-wise operations (SEAL), OT-based
secure comparison (emp-ot), and HE matrix operations.

**Output format**:

```
Rebuilding BLB with ASAN+UBSAN...
...
BUILD_DONE

--- ASAN: test_ntt ---
...
NTT_EXIT=0

--- ASAN: test_linear_operator ---
...
LO_EXIT server=0 client=0
NO_SANITIZER_ERRORS_LO

--- ASAN: test_fixpoint ---
...
FP_EXIT server=0 client=0
NO_SANITIZER_ERRORS_FP

--- ASAN: test_matmul ---
...
MM_EXIT server=0 client=0
NO_SANITIZER_ERRORS_MM

ASAN_ALL_DONE
```

If a sanitizer error occurs, the ASAN/UBSAN runtime prints a detailed report to stderr
including the error type, stack trace, and memory state. The script also greps server logs
for `error|sanitize|ubsan|asan` patterns.

---

### cross_validate.sh

**Location**: `docker/v1.0/scripts/cross_validate.sh`
**Purpose**: Runs C++ test binaries and validates their output against a Python reference
implementation. Confirms that the MPC protocol produces cryptographically correct results,
not just exit code 0.

**How to run**:

```bash
docker run --name blb_xval --entrypoint /docker-scripts/cross_validate.sh blb:v1.0

# View output
docker logs blb_xval

# Clean up
docker rm blb_xval
```

**Validation 1: test_fixpoint (less_than_constant)**

The C++ test generates 32 random values in `[0, 2^16)` at 16-bit precision, computes
`less_than_constant(x, 3, bitwidth=16)` using the IKNP OT protocol (XOR-shared between
two parties), reconstructs the result on the client (BOB) side, and checks each case.

The Python reference validates the **logic**: for signed 16-bit representation,
values in `[0, 32767]` are positive, values in `[32768, 65535]` represent negative numbers
(two's complement). `less_than_constant(x, 3)` should return 1 iff `signed(x) < 3`.

Edge cases verified:
- `0 < 3 = True` (smallest positive)
- `2 < 3 = True` (just below constant)
- `3 < 3 = False` (equal, not less-than)
- `65535 (-1 signed) < 3 = True` (negative < positive)
- `32768 (-32768 signed) < 3 = True` (most negative value)

**Validation 2: test_linear_operator (HE element-wise multiply)**

Runs the C++ test, captures output from both server and client. The test computes `x^2`
and `x*y` element-wise on 8192 CKKS slots (BFV ring dimension N=8192) with signed inputs
in `[-5, 5]`. The reconstructed ciphertext values are checked against expected plaintext
values by the C++ test itself; the script confirms both parties exit cleanly.

**Output**: ends with `Cross-Validation Complete` banner. Look for
`[less_than_constant] all N cases matched` in the C++ output to confirm fixpoint correctness.

---

### gen_report_table.py

**Location**: `docker/v1.0/scripts/gen_report_table.py`
**Purpose**: Reads JSON benchmark result files and emits a LaTeX table suitable for
inclusion in the evaluation section of a paper.

**Usage**:

```bash
# Inside the container (default path: /blb/results/)
python3 /docker-scripts/gen_report_table.py

# Custom path
python3 /docker-scripts/gen_report_table.py /path/to/results/

# From the host (mount results directory)
docker compose run --rm blb bash -c "python3 /docker-scripts/gen_report_table.py"
```

**Input**: directory containing `*.json` files in the format produced by `benchmark.sh`.
Files are sorted alphabetically by filename.

**Output**: LaTeX `table` environment with `booktabs` formatting:

```latex
\begin{table}[t]
  \centering
  \caption{BLB microbenchmark results (CPU, single-machine two-party).}
  \label{tab:blb-microbenchmarks}
  \begin{tabular}{lrrr}
    \toprule
    \textbf{Test} & \textbf{Time (ms)} & \textbf{Comm.\ Server (B)} & \textbf{Comm.\ Client (B)} \\
    \midrule
    test\_ntt & $11.0 \pm 0.0$ & 0 & 0 \\
    ...
    \bottomrule
  \end{tabular}
\end{table}
```

**Dependencies**: python3, json, pathlib (all in standard library, no pip packages needed).

---

### build_blb.sh

**Location**: `docker/v1.0/scripts/build_blb.sh`
**Purpose**: Quick rebuild of BLB only. Assumes all dependencies (SEAL, HEXL, emp-tool,
emp-ot) are already built in the Docker image. Useful after modifying C++ source files
without rebuilding the entire image.

**Usage**:

```bash
docker compose run --rm blb build
```

**What it does**:

```bash
cd /blb
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DUSE_HE_GPU=OFF
cmake --build build -j$(nproc)
```

**When to use**: After editing C++ test files or library code while in an interactive
`docker compose run --rm blb bash` session. Changes are lost when the container exits
(unless you're using a bind mount).

---

### run_server.sh

**Location**: `docker/v1.0/scripts/run_server.sh`
**Purpose**: Starts the server (ALICE, r=1) role for two-container mode. Used when you want
to run server and client in separate Docker containers (e.g., on different machines or for
network measurement).

**Environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `BLB_PORT` | `1234` | TCP port to listen on |
| `TEST_NAME` | `test_cir_linear` | Which test binary to execute |

**Usage**:

```bash
# Start server container
docker compose run --rm -e TEST_NAME=test_matmul blb server
```

**What it does**: Executes `exec /blb/build/Test/${TEST_NAME} r=1 p=${PORT}` — the `exec`
replaces the shell process so signals (Ctrl-C) go directly to the test binary.

---

### run_client.sh

**Location**: `docker/v1.0/scripts/run_client.sh`
**Purpose**: Starts the client (BOB, r=2) role for two-container mode. Waits for the server
to be reachable, then connects.

**Environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `BLB_PORT` | `1234` | TCP port to connect to |
| `BLB_SERVER_IP` | `blb-server` | Server hostname/IP (Docker service name or IP) |
| `TEST_NAME` | `test_cir_linear` | Which test binary to execute |

**Usage**:

```bash
# Start client container (after server is running)
docker compose run --rm -e TEST_NAME=test_matmul blb client
```

**Server wait mechanism**: Uses `nc -z` in a retry loop (40 attempts, 0.5s apart = 20s max).
Note: this is safe here because the `nc -z` targets the Docker network between containers,
not localhost — the server's `accept()` is consumed by the real client process, not by `nc`.
(The `nc -z` bug only affects single-container mode where server and client share the same
network namespace.)

---

## Host-Side Scripts

These scripts run on the host machine. They invoke Docker commands.

### run_tmux.sh

**Location**: `docker/v1.0/scripts/run_tmux.sh`
**Purpose**: Launches a tmux session with two panes — server (ALICE) in the top pane and
client (BOB) in the bottom pane — each running in a separate Docker container. Gives you
a live split-screen view of both parties during a two-party test.

**Prerequisites**: `tmux` and `docker compose` must be installed on the host.

**Usage**:

```bash
cd docker/v1.0

# Default test (test_cir_linear)
./scripts/run_tmux.sh

# Specific test
./scripts/run_tmux.sh test_matmul

# List available tests
./scripts/run_tmux.sh --list
```

**Arguments**:

| Argument | Description |
|----------|-------------|
| (none) | Run `test_cir_linear` (default) |
| `TEST_NAME` | Run the specified test |
| `--list` | Print available test names and exit |

**What it does**:

1. Tears down any previous Docker containers (`docker compose down`)
2. Builds the image if needed (`docker compose build`)
3. Kills any existing tmux session named `blb-test`
4. Creates a new tmux session with:
   - Top pane: `docker compose run --rm blb-server` (ALICE)
   - Bottom pane: waits 5 seconds, then `docker compose run --rm blb-client` (BOB)
5. Attaches to the tmux session
6. On exit: runs `docker compose down --remove-orphans` to clean up

**Environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `BLB_PORT` | `1234` | TCP port for the two-party protocol |

**Tmux controls**:
- `Ctrl-B "` — split the current pane (if you want more)
- `Ctrl-B o` — switch between panes
- `Ctrl-B d` — detach (containers keep running)
- `tmux attach -t blb-test` — reattach

---

## Utility Scripts

### throttle.sh

**Location**: repo root (`throttle.sh`)
**Purpose**: Network throttling using Linux `tc` (traffic control). Simulates various
network conditions for benchmarking two-party protocols over real or emulated WAN links.
Originally from [emp-toolkit](https://github.com/emp-toolkit/emp-readme/blob/master/scripts/throttle.sh).

**Usage**:

```bash
# Simulate LAN (~3 Gbps, 0.5ms RTT)
sudo ./throttle.sh lan eth0

# Simulate WAN (~400 Mbps, 4ms RTT)
sudo ./throttle.sh wan1 eth0

# Simulate WAN (~800 Mbps, 80ms RTT)
sudo ./throttle.sh wan2 eth0

# Simulate WAN (~1.6 Gbps, 40ms RTT)
sudo ./throttle.sh wan3 eth0

# Simulate WAN (~1.6 Gbps, 80ms RTT)
sudo ./throttle.sh wan4 eth0

# Remove all throttling
sudo ./throttle.sh del eth0
```

**Profiles**:

| Profile | Bandwidth | Added Latency (one-way) | RTT |
|---------|-----------|------------------------|-----|
| `lan` | 3 Gbps | 0.25 ms | ~0.5 ms |
| `wan1` | 400 Mbps | 2 ms | ~4 ms |
| `wan2` | 800 Mbps | 40 ms | ~80 ms |
| `wan3` | 1.6 Gbps | 20 ms | ~40 ms |
| `wan4` | 1.6 Gbps | 40 ms | ~80 ms |

**Requires**: root/sudo, Linux `tc` and `netem` kernel modules. Does not work on macOS.

**Warning**: This script modifies the host machine's network stack. Use on a dedicated
testbed, not a shared machine. Always run `./throttle.sh del DEV` when done.

---

## Environment Variables

All environment variables used across scripts, consolidated:

| Variable | Default | Used By | Description |
|----------|---------|---------|-------------|
| `BLB_PORT` | `1234` | run_tests, run_manual, benchmark, run_server, run_client, run_tmux | TCP port for two-party MPC protocol |
| `BLB_SERVER_IP` | `127.0.0.1` | run_client, docker-compose | Server address (hostname or IP) |
| `TEST_TIMEOUT` | `600` | run_tests, run_tests_gpu | Per-test timeout in seconds |
| `TEST_NAME` | `test_cir_linear` | run_server, run_client | Test binary name for two-container mode |
| `BUILD_JOBS` | `0` (= nproc) | Dockerfile | Parallel make jobs during image build |
| `IMAGE_TAG` | `blb:v1.0` | docker-compose | Docker image name:tag |
| `ASAN_OPTIONS` | (unset) | run_asan | Set to `detect_leaks=0` inside the script |
| `UBSAN_OPTIONS` | (unset) | run_asan | Set to `print_stacktrace=1` inside the script |

---

## Port Detection: Why Not nc -z

All scripts that wait for a server to open a port use `/proc/net/tcp` instead of `nc -z`.
This is documented here because it is a critical, non-obvious design decision.

**The problem**: BLB's NetIO layer (`Utils/net_io_channel.h`) opens a TCP socket, calls
`listen()`, then does exactly **one** `accept()`. After accepting a connection, it closes
the listening socket. The `nc -z` command works by opening a TCP connection to the port
and immediately closing it — this is the connection that `accept()` returns. When the real
client then tries to connect, the listening socket is already closed, and the connection
is refused.

**The fix**: Instead of connecting to the port, we check whether the port is in LISTEN
state by reading `/proc/net/tcp`:

```bash
hex_port=$(printf '%04X' "$PORT")
grep -q ":${hex_port} 00000000:0000 0A" /proc/net/tcp 2>/dev/null
```

The `0A` at the end is the TCP state code for LISTEN. The `00000000:0000` is the remote
address (0.0.0.0:0, meaning "listening, not connected to anyone"). This is a read-only
operation — it does not consume the accept.

**Exception**: `run_client.sh` uses `nc -z` because it runs in a separate container from
the server. The `nc -z` targets the Docker bridge network, and the real client connects
from the same container. The server's `accept()` is consumed by the real client, not by
`nc -z` from another container. This is safe.

---

## Adding a New Script

1. Create the script in `docker/v1.0/scripts/` (or `v1.0-gpu/scripts/` if GPU-specific)
2. Make it executable: `chmod +x your_script.sh`
3. If it should be accessible via `docker compose run blb your_command`:
   - Add a case to `entrypoint.sh`
   - Use `shift` before `exec` if the script accepts arguments
4. If it needs entrypoint bypass (like `run_asan.sh`):
   - Run with `docker run --entrypoint /docker-scripts/your_script.sh blb:v1.0`
5. The Dockerfile copies all scripts: `RUN cp -r docker/v1.0/scripts /docker-scripts`
   — no Dockerfile changes needed unless you add a new scripts directory
6. Rebuild the image: `docker compose build`
7. Document it in this file
