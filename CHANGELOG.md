# Changelog

All notable changes to the BLB (Breaking the Layer Barrier) framework are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-06-23

### Added

#### Docker Infrastructure
- **CPU Docker image** (`blb:v1.0`): fully reproducible build environment on Ubuntu 22.04 with
  SEAL 4.1.2, Intel HEXL 1.2.6, emp-tool, and emp-ot. Single `docker compose up` builds
  everything from source and runs the full test suite.
- **GPU Docker image** (`blb:v1.0-gpu`): CUDA 12.2 variant using `nvidia/cuda:12.2.0-devel-ubuntu22.04`
  base image. Adds PhantomFHE GPU HE backend and builds with `-DUSE_HE_GPU=ON`. Enables GPU
  tests (test_HE, testHEGPU, testFFN) that are skipped in the CPU build. Requires
  `nvidia-container-toolkit` on the host. Not validated (no GPU available on testbed).
- **Docker Compose** configuration for both CPU and GPU images with environment variable
  tunables (`BLB_PORT`, `BLB_SERVER_IP`, `BUILD_JOBS`, `IMAGE_TAG`).
- **Container healthcheck**: `test_ntt` runs as a Docker HEALTHCHECK (single-party, fast,
  exercises HEXL/SEAL path).
- **OCI labels** on Docker images (title, description, version, authors, source).

#### Test & Benchmark Scripts
- **`run_tests.sh`**: automated CPU test runner. Executes all 7 CPU tests (1 single-party,
  6 two-party) in a single container on localhost, reports pass/fail/skip with colored output.
  Uses `/proc/net/tcp` for port detection instead of `nc -z` (which consumes the server's
  single `accept()` call and breaks all two-party tests).
- **`run_tests_gpu.sh`**: GPU variant that additionally enables test_HE, testHEGPU, testFFN.
- **`run_manual.sh`**: interactive test selector. Supports `--list` to enumerate available
  tests, `--test <name>` to run a single test, or no arguments to run all. Accessible from
  the host via `docker compose run blb manual`.
- **`run_tmux.sh`**: host-side script that launches server and client in separate Docker
  containers with a tmux split view for live two-party observation.
- **`benchmark.sh`**: benchmarking harness. Runs any test N times, captures wall-clock time
  via `date +%s%N`, extracts communication bytes from test output, and writes structured JSON
  results. Supports single-party test detection. Uses python3 for statistics (mean, std)
  instead of `bc` (not available in the container image).
- **`run_asan.sh`**: standalone ASAN/UBSAN script. Rebuilds BLB from scratch with
  `-fsanitize=address,undefined -fno-omit-frame-pointer`, then runs test_ntt,
  test_linear_operator, test_fixpoint, and test_matmul under sanitizer instrumentation.
  Sets `ASAN_OPTIONS=detect_leaks=0` (SEAL's static allocations trigger false positives)
  and `UBSAN_OPTIONS=print_stacktrace=1`.
- **`cross_validate.sh`**: runs test_fixpoint and test_linear_operator, then validates their
  output against a Python reference implementation. Confirms MPC protocol correctness for
  signed two's complement comparison (16-bit, constant=3) and HE element-wise multiply
  (8192 CKKS slots).
- **`gen_report_table.py`**: reads `results/*.json` and emits a LaTeX table for the
  evaluation section. Accepts a CLI path argument (default: `/blb/results`).
- **`build_blb.sh`**: quick rebuild script (assumes dependencies already built in the image).
- **`run_server.sh`** / **`run_client.sh`**: two-container mode helpers for server (ALICE)
  and client (BOB) roles.
- **`entrypoint.sh`**: Docker entrypoint dispatcher. Routes `test`, `build`, `server`,
  `client`, `benchmark`, `manual`, `bash` commands to the appropriate script.

#### CI/CD
- **`.gitlab-ci.yml`**: 3-stage pipeline (build, test, report).
  - `test-cpu`: runs on every push, requires `docker` + `amd64` runner tags.
  - `test-gpu`: manual trigger, `allow_failure: true`, requires `docker` + `amd64` + `gpu` tags.

#### Results & Documentation
- **`RESULTS.md`**: comprehensive results document at repo root. Contains test suite status
  (7 pass, 0 fail, 3 skip), benchmark data with timing breakdown and analysis, stability
  results (3x consistency, ASAN/UBSAN, Python cross-validation), Docker image inventory,
  and reproduction instructions.
- **`results/*.json`**: structured benchmark data for all 7 CPU tests (test_ntt,
  test_linear_operator, test_matmul, test_Conv, test_cir_conv, test_fixpoint, test_cir_linear).
  Each file contains mean, std, per-run values, and communication bytes.
- **`report/sections/evaluation.tex`**: LaTeX evaluation section with testbed table, benchmark
  results table, timing analysis, PrivCirNet comparison, and limitations discussion.
- **`docker/README.md`**: Docker environment documentation covering requirements, versions,
  quick start for CPU and GPU, GitLab CI runner setup, environment variables, and test suite
  overview.
- **`scripts/README.md`**: detailed reference for all build and execution scripts with
  usage examples, argument documentation, environment variables, and architecture notes.

### Fixed

- **`nc -z` port check consuming server accept**: the original approach used
  `nc -z 127.0.0.1 PORT` to detect when the server was ready. Because BLB's NetIO layer
  does a single `accept()` then closes the listening socket, `nc -z` would consume that
  accept, leaving the real client with a refused connection. Replaced with `/proc/net/tcp`
  LISTEN-state check (`grep :HEXPORT ... 0A`), which is read-only and does not consume
  the accept.
- **`bc` not available in Docker image**: `benchmark.sh` originally used `bc` for mean/std
  computation. The Ubuntu 22.04 minimal image does not include `bc`. Replaced with `python3`
  (already installed for `gen_report_table.py`).
- **Single-party test treated as two-party in benchmark**: `test_ntt` is single-party (no
  server/client), but `benchmark.sh` tried to start it in two-party mode. Added
  `SINGLE_PARTY_TESTS` detection variable.
- **Docker Compose `version: "3.9"` deprecation warning**: removed the `version` key from
  both `docker-compose.yml` files (deprecated in Compose V2).

### Validated

- **3x consistency**: all 7 CPU tests pass identically across 3 consecutive full-suite runs.
  No non-determinism or port conflicts observed.
- **ASAN/UBSAN**: 4 tests (test_ntt, test_linear_operator, test_fixpoint, test_matmul) pass
  with zero AddressSanitizer or UndefinedBehaviorSanitizer errors under debug instrumented build.
- **Python cross-validation**: `test_fixpoint` less_than_constant logic verified against Python
  reference for signed 16-bit comparison (all 32 cases matched). `test_linear_operator` HE
  element-wise multiply verified on 8192 CKKS slots with signed inputs in [-5, 5].

### Known Issues

- `test_HE` is mislabeled: despite the name suggesting CPU HE, it uses `Datatype::DEVICE`
  and requires GPU (PhantomFHE). Only runs in the v1.0-gpu image.
- NetIO (`Utils/net_io_channel.h`) uses `fread()` in a busy-spin loop on EOF. If the peer
  disconnects unexpectedly, the process burns 100% CPU until killed.
- Communication bytes are not reliably captured from all test binaries. Only some tests print
  the `total data sent till now` line.
- GPU image (`blb:v1.0-gpu`) is untested — no NVIDIA GPU available on the testbed.

## [0.x] - Pre-Docker (original codebase)

The original BLB codebase as published with the USENIX Security 2025 paper. Manual build
process requiring direct installation of SEAL, HEXL, emp-tool, emp-ot, and optionally
PhantomFHE. No Docker support, no automated test runner, no CI/CD.
