# ============================================================
# BLB v1.0-gpu — Privacy-Preserving Deep Learning Framework
# Target: linux/amd64 with NVIDIA CUDA >= 12.2
# GPU: enabled (USE_HE_GPU=ON, PhantomFHE backend)
# ============================================================

FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

LABEL org.opencontainers.image.title="BLB-GPU" \
      org.opencontainers.image.description="Breaking the Layer Barrier — hybrid CKKS+MPC with GPU-accelerated HE via PhantomFHE (USENIX Security 2025)" \
      org.opencontainers.image.version="1.0-gpu" \
      org.opencontainers.image.authors="SEC-LAB-PPDL, TII" \
      org.opencontainers.image.source="https://gitlab.com/ppdl/blb"

ARG DEBIAN_FRONTEND=noninteractive
# 0 = auto-detect via nproc
ARG BUILD_JOBS=0
ARG SEAL_VERSION=4.1.2
ARG HEXL_VERSION=1.2.6

# ── System packages ──────────────────────────────────────────
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

RUN cp -r docker/v1.0-gpu/scripts /docker-scripts && chmod +x /docker-scripts/*.sh

# ── Patches ──────────────────────────────────────────────────
RUN cd Extern/SEAL     && patch -p1 --forward --reject-file=/dev/null < ../patch/seal-ckks.patch   || true
RUN cd Extern/emp-tool && patch -p1 --forward --reject-file=/dev/null < ../patch/emp-tool.patch  || true
RUN cd Extern/emp-ot   && patch -p1 --forward --reject-file=/dev/null < ../patch/emp-ot.patch    || true
RUN cd Extern/phantom-fhe && patch -p1 --forward --reject-file=/dev/null < ../patch/phantom.patch || true

# ── Build HEXL ───────────────────────────────────────────────
RUN cd Extern/hexl && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/blb/Extern/hexl/hexl_build \
        -DHEXL_TESTING=OFF \
        -DHEXL_BENCHMARK=OFF && \
    cmake --build build -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS}) && \
    cmake --install build

# ── Build SEAL ───────────────────────────────────────────────
RUN cd Extern/SEAL && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DSEAL_USE_INTEL_HEXL=ON \
        -DCMAKE_PREFIX_PATH=/blb/Extern/hexl/hexl_build \
        -DSEAL_BUILD_TESTS=OFF \
        -DSEAL_BUILD_EXAMPLES=OFF && \
    cmake --build build -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS})

# ── Build PhantomFHE (GPU HE backend) ───────────────────────
RUN cd Extern/phantom-fhe && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES=native \
        -DCMAKE_INSTALL_PREFIX=build_phantom && \
    cmake --build build --target install -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS})

# ── Build BLB (GPU enabled) ─────────────────────────────────
RUN cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_HE_GPU=ON && \
    cmake --build build -j$([ "${BUILD_JOBS}" -eq 0 ] && nproc || echo ${BUILD_JOBS})

# ── Healthcheck ──────────────────────────────────────────────
HEALTHCHECK --interval=300s --timeout=30s --start-period=10s --retries=1 \
  CMD ["/blb/build/Test/test_ntt"]

# ── Entrypoint ───────────────────────────────────────────────
ENTRYPOINT ["/docker-scripts/entrypoint.sh"]
CMD ["test"]
