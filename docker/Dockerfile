ARG BASE_IMAGE
FROM ${BASE_IMAGE}

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

# Fail-fast code-quality guardrail per hostbootstrap's code_check_doctrine.md.
# Runs before the foreign-backend builds so style/lint violations abort the
# image build in seconds, not after the multi-minute PGO/BOLT pipelines.
RUN mcts check-code

RUN mcts build cpp-legacy \
    && mcts build cpp-imperative \
    && mcts build cpp-functional \
    && mcts build rust
