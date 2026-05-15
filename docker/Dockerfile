FROM ubuntu:24.04

ARG GHC_VERSION=9.14.1
ARG CABAL_VERSION=3.16.1.0
ARG STYLE_GHC_VERSION=9.12.4
ARG FOURMOLU_VERSION=0.19.0.1
ARG HLINT_VERSION=3.10
ARG STYLE_TOOLS_DIR=/opt/mcts-style-tools/bin
ARG LLVM_VERSION=19
ARG RUST_VERSION=1.95.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        bolt-19 \
        ca-certificates \
        clang-19 \
        curl \
        g++ \
        gcc \
        git \
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
ENV MCTS_STYLE_TOOLS_DIR=${STYLE_TOOLS_DIR}
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
    && if [ -x "/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-bolt" ]; then ln -sf "/usr/lib/llvm-${LLVM_VERSION}/bin/llvm-bolt" /usr/local/bin/llvm-bolt; fi

ENV LLVM_CONFIG=/usr/local/bin/llvm-config
ENV CC=gcc
ENV CXX=g++
ENV RUSTUP_TOOLCHAIN=${RUST_VERSION}

WORKDIR /workspace/MCTS
