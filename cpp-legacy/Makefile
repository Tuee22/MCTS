.PHONY: smoke all clean legacy-to-wire

all: smoke

smoke:
	mkdir -p build
	$(CXX) -std=c++17 -O3 -fPIC -Wall -Wno-pessimizing-move -Ilegacy-core -shared \
		legacy-core/board.cpp c-abi/mcts_cpp_legacy.cc c-abi/rng.cc \
		-o build/libmcts_cpp_legacy.so
	$(CXX) -std=c++17 -O3 -fPIC -Wall -Wno-pessimizing-move -shared \
		c-abi/rng.cc \
		-o build/libmcts_cpp_rng.so
	$(MAKE) envelope-build-id

# Post-link envelope patch per
# DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md → Sprint 4.2.
# Hashes the linked shared library and writes the digest into the
# `.envelope_build_id` ELF section so `mcts_legacy_get_envelope()`
# reports it as `engine_build_id`. The patch is bytewise idempotent
# across rebuilds with no content changes.
envelope-build-id:
	@if command -v objcopy >/dev/null 2>&1; then \
		sha=$$(sha256sum build/libmcts_cpp_legacy.so | cut -c1-64); \
		python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))" "$$sha" \
			> build/.envelope_build_id.bin; \
		objcopy --update-section .envelope_build_id=build/.envelope_build_id.bin \
			build/libmcts_cpp_legacy.so 2>/dev/null || true; \
	fi

# One-time Q6 fixture generator. Plays G_LP=10 selfplay games with the
# legacy parity envelope (seed=S_LP=42, sims=S_LP_SIMS=10000,
# max_plies=10000) and writes wire-format .tr files under
# an explicit external or ignored output root. Documented in
# documents/engineering/cli_command_surface.md.
legacy-to-wire:
	mkdir -p build
	$(CXX) -std=c++17 -O3 -Wall -Wno-pessimizing-move -Ilegacy-core \
		legacy-core/board.cpp tools/legacy-to-wire.cc \
		-o build/legacy-to-wire

clean:
	rm -rf build
