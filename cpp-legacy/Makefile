.PHONY: smoke all clean legacy-to-wire

# Sprint 4.6: backend (i) cpp-legacy pivoted from g++ to clang++-19 to
# match backend (ii) (Sprint 5.9) and prepare for the Sprint 4.7
# Dockerfile gcc/g++ scrub. The legacy engine source under
# `legacy-core/` is preserved verbatim; only the build harness flips.
# `:=` (not `?=`) so the Dockerfile's `ENV CXX=g++` does not silently
# override; a command-line `make CXX=...` still wins per GNU make's
# variable precedence rules.
CXX := clang++-19

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
# Sprint 4.6: prefer `llvm-objcopy-19` so the patch keeps working under
# the Sprint 4.7 Dockerfile scrub that removes GNU `objcopy` along
# with gcc/g++. The GNU binary remains as a fallback for host
# diagnostics outside the container.
envelope-build-id:
	@objcopy_tool=$$(command -v llvm-objcopy-19 || command -v llvm-objcopy || command -v objcopy || true); \
	if [ -n "$$objcopy_tool" ]; then \
		sha=$$(sha256sum build/libmcts_cpp_legacy.so | cut -c1-64); \
		python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))" "$$sha" \
			> build/.envelope_build_id.bin; \
		"$$objcopy_tool" --update-section .envelope_build_id=build/.envelope_build_id.bin \
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
