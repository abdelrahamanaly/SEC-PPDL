# ============================================================
# BLB v1.0 — Privacy-Preserving Deep Learning Framework
# Target: linux/amd64 (x86_64 required — HEXL & emp-tool use
#         AVX2/AES/SSE4.1 intrinsics not available on ARM)
# GPU: disabled (USE_HE_GPU=OFF)
# ============================================================

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="BLB" \
      org.opencontainers.image.description="Breaking the Layer Barrier — hybrid CKKS+MPC framework for private Transformer inference (USENIX Security 2025)" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.authors="SEC-LAB-PPDL, TII" \
      org.opencontainers.image.source="https://gitlab.com/ppdl/blb"

ARG DEBIAN_FRONTEND=noninteractive
# 0 = auto-detect via nproc
ARG BUILD_JOBS=0
ARG SEAL_VERSION=4.1.2
ARG HEXL_VERSION=1.2.6

# ── System packages ──────────────────────────────────────────
# Versions pinned to Ubuntu 22.04 (jammy) for reproducibility.
# Exact patch versions are not pinned — they shift with security
# updates and would break `--no-cache` builds within weeks.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        patch \
        libssl-dev \
        libgmp-dev \
        libboost-system-dev \
        libboost-thread-dev \
        netcat-openbsd \
        python3 \
        python3-pip \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ── Source ───────────────────────────────────────────────────
WORKDIR /blb
COPY . .

# Copy docker helper scripts into a known location inside the image
RUN cp -r docker/v1.0/scripts /docker-scripts && chmod +x /docker-scripts/*.sh

# ── Patches ──────────────────────────────────────────────────
# Use `patch` instead of `git apply` so it works without git metadata.
# These are idempotent: the CI cache layer is invalidated only when
# the patch files themselves change.
RUN cd Extern/SEAL    && patch -p1 --forward --reject-file=/dev/null < ../patch/seal-ckks.patch   || true
RUN cd Extern/emp-tool && patch -p1 --forward --reject-file=/dev/null < ../patch/emp-tool.patch  || true
RUN cd Extern/emp-ot   && patch -p1 --forward --reject-file=/dev/null < ../patch/emp-ot.patch    || true

# ── Build HEXL ───────────────────────────────────────────────
# Intel HEXL provides AVX-512 / AVX2 accelerated NTT used by
# both SEAL and the Utils library.
RUN cd Extern/hexl && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/blb/Extern/hexl/hexl_build \
        -DHEXL_TESTING=OFF \
        -DHEXL_BENCHMARK=OFF && \
    cmake --build build -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS}) && \
    cmake --install build

# ── Build SEAL ───────────────────────────────────────────────
# Must be built at Extern/SEAL/build (hardcoded path in HE/CMakeLists.txt).
RUN cd Extern/SEAL && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DSEAL_USE_INTEL_HEXL=ON \
        -DCMAKE_PREFIX_PATH=/blb/Extern/hexl/hexl_build \
        -DSEAL_BUILD_TESTS=OFF \
        -DSEAL_BUILD_EXAMPLES=OFF && \
    cmake --build build -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS})

# ── Build BLB ────────────────────────────────────────────────
RUN cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_HE_GPU=OFF && \
    cmake --build build -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS})

# ── Healthcheck ──────────────────────────────────────────────
# NTT is single-party, fast (~1s), and exercises the HEXL/SEAL path.
HEALTHCHECK --interval=300s --timeout=30s --start-period=10s --retries=1 \
  CMD ["/blb/build/Test/test_ntt"]

# ── Entrypoint ───────────────────────────────────────────────
ENTRYPOINT ["/docker-scripts/entrypoint.sh"]
CMD ["test"]
