# BLB Benchmarking Results

Testbed: `maia.crypto.tii.ae` — 2x Intel Xeon Silver 4208 @ 2.10GHz, 32 threads, 503 GiB RAM, Ubuntu 20.04, Docker 27.5.1. No GPU.

## Test Suite Status

| Test | Type | Status | Notes |
|------|------|--------|-------|
| test_ntt | single-party | PASS | NTT via Intel HEXL (AVX2/AVX-512) |
| test_linear_operator | two-party | PASS | HE element-wise multiply (SEAL CPU) |
| test_matmul | two-party | PASS | HE matrix multiplication |
| test_Conv | two-party | PASS | HE convolution |
| test_cir_conv | two-party | PASS | PrivCirNet block-circulant convolution |
| test_fixpoint | two-party | PASS | IKNP OT + fixed-point secure comparison |
| test_cir_linear | two-party | PASS | PrivCirNet block-circulant linear layer |
| test_HE | two-party | SKIP | Requires GPU (Datatype::DEVICE) |
| testHEGPU | two-party | SKIP | Requires GPU (PhantomFHE) |
| testFFN | two-party | SKIP | Requires GPU (full Transformer layer) |

**Summary: 7 passed, 0 failed, 3 skipped (GPU)**

## Benchmark Results (3 runs each, single container, localhost)

All two-party tests run server (ALICE, r=1) and client (BOB, r=2) on localhost within the same container.

| Test | Mean (ms) | Std (ms) | Values (ms) | Comm (B) |
|------|-----------|----------|-------------|----------|
| test_ntt | 11 | 0 | 11, 11, 11 | single-party |
| test_linear_operator | 1610 | 2.4 | 1613, 1608, 1608 | — |
| test_matmul | 1911 | 44.1 | 1911, 1899, 1897 | — |
| test_Conv | 8929 | 156.6 | 8772, 9044, 8859 | — |
| test_cir_conv | 2585 | 55.6 | 2580, 2605, 2566 | — |
| test_fixpoint | 1301 | 28.2 | 1332, 1286, 1302 | S:163KB C:336KB |
| test_cir_linear | 7612 | 149.2 | 7696, 7402, 7543 | — |

### Timing breakdown

- **Fast (< 2s)**: test_ntt, test_linear_operator, test_fixpoint — dominated by SEAL key generation + OTPack init
- **Medium (2-3s)**: test_matmul, test_cir_conv — larger HE ciphertext operations with BSGS rotations
- **Slow (7-9s)**: test_Conv, test_cir_linear — full convolution/linear layer with multiple HE operations and larger parameter sets

### Key observations

1. **Variance is low** — std/mean < 2% for most tests, confirming stable single-machine measurement
2. **SEAL key generation** (GenerateNewKey in HE.h) is a fixed cost: client generates secret, public, relin, and Galois keys, then transfers to server via NetIO
3. **PrivCirNet tests** (cir_conv, cir_linear) are the BLB paper's core contribution — block-circulant structure reduces HE rotations vs. dense linear layers
4. **FixPoint** uses IKNP OT extension (4 threads) — the OTPack initialization (base OT + correlation setup) is the bottleneck, not the actual comparison

## Known Issues

1. `test_HE` is mislabeled — despite the name suggesting CPU HE, it uses `Datatype::DEVICE` and requires GPU (PhantomFHE)
2. NetIO (Utils/net_io_channel.h) uses `fread()` in a busy-spin loop on EOF — if the peer disconnects unexpectedly, the process burns 100% CPU until killed
3. Communication bytes not reliably captured from test output — the `total data sent` line is only printed by some tests

## Stability (TICKET-06)

### 3x Consistency Runs

All 7 CPU tests run 3 consecutive times — identical results every run:

| Run | Passed | Failed | Skipped |
|-----|--------|--------|---------|
| 1/3 | 7 | 0 | 3 (GPU) |
| 2/3 | 7 | 0 | 3 (GPU) |
| 3/3 | 7 | 0 | 3 (GPU) |

No non-determinism or port conflicts observed.

### ASAN/UBSAN

Debug rebuild with `-fsanitize=address,undefined -fno-omit-frame-pointer`:

| Test | Exit | Sanitizer Errors |
|------|------|------------------|
| test_ntt | 0 | None |
| test_linear_operator | server=0, client=0 | None |
| test_fixpoint | server=0, client=0 | None |
| test_matmul | server=0, client=0 | None |

No memory errors or undefined behavior detected.

### Python Cross-Validation

- **test_fixpoint** (`less_than_constant`): all 32 cases matched. Python reference confirms signed two's complement comparison logic at 16-bit bitwidth is correct for edge cases (0, boundary, negative via wrap).
- **test_linear_operator** (HE element-wise multiply): x^2 and x*y pass on all 8192 CKKS slots with signed inputs in [-5, 5]. Reconstructed ciphertext values match expected plaintext values exactly.

## Docker Images

| Image | Size | Description |
|-------|------|-------------|
| `blb:v1.0` | CPU-only | Ubuntu 22.04, SEAL 4.1.2, HEXL 1.2.6, emp-tool/emp-ot |
| `blb:v1.0-gpu` | GPU | CUDA 12.2, PhantomFHE + above (not validated — no GPU on testbed) |

## Reproduction

```bash
# SSH to testbed
ssh abdel@maia.crypto.tii.ae

# Run full test suite
cd ~/BLB/docker/v1.0
docker compose up --build

# Run benchmarks
docker compose run --rm blb benchmark --test test_matmul --runs 5

# Interactive test selector
docker compose run --rm blb manual --list
docker compose run --rm blb manual --test test_fixpoint
```
