# BLB Docker Environments

## Requirements

- **Host architecture: x86_64 (amd64)**
  BLB uses Intel HEXL (AVX-512/AVX2/AES/SSE4.1 intrinsics) and emp-tool x86 primitives.
  It **cannot** compile on ARM (Apple Silicon, AWS Graviton, etc.).
  On an Apple Silicon Mac you must run Docker in emulation mode (`--platform linux/amd64`)
  which will be slow — a native x86 Linux machine is strongly recommended.

- **GPU support (v1.0-gpu)**: requires NVIDIA GPU with compute capability >= 7.0,
  CUDA >= 12.2, and `nvidia-container-toolkit` on the host.
  See `v1.0-gpu/` for the GPU-enabled image using PhantomFHE.

## Versions

| Directory | Description |
|-----------|-------------|
| `v1.0/`     | CPU-only, Ubuntu 22.04, SEAL 4.1.2 + HEXL 1.2.6 + emp-tool |
| `v1.0-gpu/` | GPU-enabled, CUDA 12.2, PhantomFHE + SEAL 4.1.2 + HEXL 1.2.6 + emp-tool |

## Quick Start (CPU)

```bash
cd docker/v1.0

docker compose up --build              # build + run all tests
docker compose run blb bash            # interactive shell
docker compose run blb manual          # interactive test selector
docker compose run blb manual --list   # list available tests
docker compose run blb manual --test test_matmul  # run one test
docker compose run blb benchmark --test test_matmul --runs 5  # benchmark
```

## Quick Start (GPU)

```bash
cd docker/v1.0-gpu

docker compose up --build              # build + run all tests (CPU + GPU)
docker compose run blb bash            # interactive shell
```

Requires `nvidia-container-toolkit` and a CUDA >= 12.2 GPU on the host.

## GitLab CI

A `.gitlab-ci.yml` is provided at the repo root with 3 stages: `build`, `test`, `report`.

- `test-cpu`: runs automatically on every push (requires `docker` + `amd64` runner tags)
- `test-gpu`: manual trigger, `allow_failure: true` (requires `docker` + `amd64` + `gpu` tags)

To register a GitLab runner on an x86_64 Linux host:

```bash
gitlab-runner register \
  --url https://gitlab.com \
  --token <registration-token> \
  --executor docker \
  --docker-image docker:24 \
  --docker-privileged \
  --tag-list "docker,amd64"
```

## Environment Variables

See `.env` for all tunables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BLB_PORT` | `1234` | TCP port for two-party protocol |
| `BLB_SERVER_IP` | `127.0.0.1` | Server address (single-container mode) |
| `BUILD_JOBS` | `0` | Parallel build jobs (0 = nproc) |
| `IMAGE_TAG` | `blb:v1.0` | Docker image name/tag |

## Test Suite

The test runner (`scripts/run_tests.sh`) executes:

| Test | Type | Status |
|------|------|--------|
| test_ntt | single-party | CPU ✓ |
| test_cir_linear | two-party | CPU ✓ |
| test_cir_conv | two-party | CPU ✓ |
| test_matmul | two-party | CPU ✓ |
| test_Conv | two-party | CPU ✓ |
| test_fixpoint | two-party | CPU ✓ |
| test_linear_operator | two-party | CPU ✓ |
| test_HE | two-party | GPU only (skipped) |

## Adding a New Version

```
docker/
  v1.1/          ← copy v1.0, modify Dockerfile, bump IMAGE_TAG in .env
    Dockerfile
    docker-compose.yml
    .env
    scripts/
```
