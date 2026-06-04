ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG FOURMOLU_VERSION=0.19.0.1
ARG HLINT_VERSION=3.10
ARG STYLE_TOOLS_DIR=/opt/mcts-style-tools/bin
ARG RUST_VERSION=1.95.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang-19 \
        libclang-rt-19-dev \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /usr/local/lib; \
    if [ -n "${BOLT_RT_INSTR_LIB:-}" ] && [ -f "${BOLT_RT_INSTR_LIB}" ]; then \
        ln -sf "${BOLT_RT_INSTR_LIB}" /usr/local/lib/libbolt_rt_instr.a; \
    elif [ -f /usr/lib/llvm-19/lib/libbolt_rt_instr.a ]; then \
        ln -sf /usr/lib/llvm-19/lib/libbolt_rt_instr.a /usr/local/lib/libbolt_rt_instr.a; \
    else \
        echo "missing BOLT runtime instrumentation library" >&2; \
        exit 1; \
    fi

RUN mkdir -p "${STYLE_TOOLS_DIR}" \
    && cabal update \
    && cabal install "fourmolu-${FOURMOLU_VERSION}" "hlint-${HLINT_VERSION}" \
        --installdir "${STYLE_TOOLS_DIR}" \
        --install-method=copy \
        --overwrite-policy=always

RUN rustup toolchain install "${RUST_VERSION}" --profile minimal \
    && rustup component add llvm-tools-preview rustfmt --toolchain "${RUST_VERSION}"

ENV LLVM_CONFIG=/usr/local/bin/llvm-config
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
