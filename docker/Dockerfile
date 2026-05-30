FROM ubuntu:24.04

ARG GHC_VERSION=9.14.1
ARG CABAL_VERSION=3.16.1.0
ARG STYLE_GHC_VERSION=9.12.4
ARG FOURMOLU_VERSION=0.19.0.1
ARG HLINT_VERSION=3.10
ARG STYLE_TOOLS_DIR=/opt/mcts-style-tools/bin
ARG LLVM_VERSION=19
ARG RUST_VERSION=1.95.0

# Sprint 4.7: gcc/g++ are no longer in the explicit apt-get list.
# All three C++ backend Makefiles pin `CXX := clang++-19` (Sprints
# 4.6 / 5.9 / 6.11), so no first-class backend build path needs g++.
# `build-essential` is retained for `make`, `libc6-dev`, and
# `libstdc++-dev` (it still pulls g++/gcc transitively today; a future
# image revision can unpack the meta-package further if the apt-time
# savings justify it).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        bolt-19 \
        ca-certificates \
        clang-19 \
        curl \
        git \
        libclang-rt-19-dev \
        libffi-dev \
        libgmp-dev \
        libmimalloc-dev \
        lld-19 \
        llvm-19 \
        llvm-19-dev \
        pkg-config \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=/root/.ghcup/bin:/root/.cargo/bin:/usr/local/bin:$PATH
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN set -eux; \
    case "$(uname -m)" in \
        x86_64) ghcup_arch=x86_64 ;; \
        aarch64|arm64) ghcup_arch=aarch64 ;; \
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl --proto '=https' --tlsv1.2 -sSfL \
        "https://downloads.haskell.org/~ghcup/${ghcup_arch}-linux-ghcup" \
        -o /usr/local/bin/ghcup; \
    chmod +x /usr/local/bin/ghcup

RUN ghcup install ghc "${GHC_VERSION}" \
    && ghcup set ghc "${GHC_VERSION}" \
    && ghcup install cabal "${CABAL_VERSION}" \
    && ghcup set cabal "${CABAL_VERSION}"

RUN ghcup install ghc "${STYLE_GHC_VERSION}" \
    && mkdir -p "${STYLE_TOOLS_DIR}" \
    && cabal update \
    && cabal install "fourmolu-${FOURMOLU_VERSION}" "hlint-${HLINT_VERSION}" \
        --with-compiler "ghc-${STYLE_GHC_VERSION}" \
        --installdir "${STYLE_TOOLS_DIR}" \
        --install-method=copy \
        --overwrite-policy=always

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain "${RUST_VERSION}" \
    && rustup component add llvm-tools-preview rustfmt

RUN ln -sf "/usr/bin/llvm-config-${LLVM_VERSION}" /usr/local/bin/llvm-config \
    && if [ -x "/usr/bin/llvm-bolt-${LLVM_VERSION}" ]; then ln -sf "/usr/bin/llvm-bolt-${LLVM_VERSION}" /usr/local/bin/llvm-bolt; fi \
    && if [ -x "/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-bolt" ]; then ln -sf "/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-bolt" /usr/local/bin/llvm-bolt; fi \
    && mkdir -p /usr/local/lib \
    && if [ -f "/usr/lib/llvm-${LLVM_VERSION}/lib/libbolt_rt_instr.a" ]; then ln -sf "/usr/lib/llvm-${LLVM_VERSION}/lib/libbolt_rt_instr.a" /usr/local/lib/libbolt_rt_instr.a; fi

ENV LLVM_CONFIG=/usr/local/bin/llvm-config
# Sprint 4.7: defaults updated so anything in the image that respects
# the environment falls back to clang. Each backend Makefile owns its
# own `CXX := clang++-19` pin and is unaffected by these vars.
ENV CC=clang-19
ENV CXX=clang++-19
ENV RUSTUP_TOOLCHAIN=${RUST_VERSION}
ENV CARGO_HTTP_TIMEOUT=120
ENV CARGO_NET_RETRY=5

WORKDIR /workspace/MCTS

COPY . /workspace/MCTS

RUN cabal build --enable-tests --enable-benchmarks all \
    && cabal build --enable-tests --enable-benchmarks \
        test:mcts-haskell-style \
        test:mcts-unit \
        test:mcts-integration \
        test:mcts-cross-backend \
        test:mcts-legacy-parity \
        test:mcts-semantic-parity \
        bench:mcts-criterion \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks test:mcts-haskell-style)" /usr/local/bin/mcts-haskell-style \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks test:mcts-unit)" /usr/local/bin/mcts-unit \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks test:mcts-integration)" /usr/local/bin/mcts-integration \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks test:mcts-cross-backend)" /usr/local/bin/mcts-cross-backend \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks test:mcts-legacy-parity)" /usr/local/bin/mcts-legacy-parity \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks test:mcts-semantic-parity)" /usr/local/bin/mcts-semantic-parity \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks bench:mcts-criterion)" /usr/local/bin/mcts-criterion \
    && install -m 0755 "$(cabal list-bin --enable-tests --enable-benchmarks exe:mcts)" /usr/local/bin/mcts

RUN mcts build cpp-legacy \
    && mcts build cpp-imperative \
    && mcts build cpp-functional \
    && mcts build rust
