.PHONY: smoke all clean envelope-build-id bench instrumented \
        pgo-generate pgo-use bolt-instrument bolt-optimize \
        pgo-bench-generate pgo-bench-use pgo-instr-generate pgo-instr-use \
        bolt-bench-instrument bolt-bench-optimize \
        bolt-instr-instrument bolt-instr-optimize install-bench

CXX ?= g++
# Doctrine C++23 base flag set per
# DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md → Sprint 5.1.
# Sprint 5.3 closure: `-fno-exceptions` enabled; the legacy
# `corridors::board::eval` / `get_terminal_eval` and `mcts.hpp`
# `lexical_cast` throws were replaced with `__builtin_trap()` because
# the imperative engine never exercises those failure paths. The C ABI
# shim's defensive `try`/`catch (...)` wrappers were also removed
# because no exception can propagate from the engine TU.
CXXFLAGS ?= -std=c++23 -O3 -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions -fPIC -Wno-pessimizing-move -Iengine
LDFLAGS ?= -shared -flto -Wl,--emit-relocs
LDLIBS ?= -lmimalloc

ENGINE_SRCS = engine/search.cpp c-abi/mcts_cpp_imperative.cc

PGO_DIR ?= pgo-profile
BOLT_DIR ?= bolt-profile

all: smoke

# Single-artefact smoke build (canonical FFI load path).
smoke:
	mkdir -p build
	$(CXX) $(CXXFLAGS) -DMCTS_IMPERATIVE_INSTRUMENTED=1 $(LDFLAGS) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative.so

# Paired build targets per Sprint 5.1: bench artefact omits the
# `read_visits` body (returns 0); instrumented artefact wires the
# real visit cache. Both go through the same engine TU.
bench:
	mkdir -p build
	$(CXX) $(CXXFLAGS) -DMCTS_IMPERATIVE_INSTRUMENTED=0 $(LDFLAGS) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_bench.so

instrumented:
	mkdir -p build
	$(CXX) $(CXXFLAGS) -DMCTS_IMPERATIVE_INSTRUMENTED=1 $(LDFLAGS) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_instrumented.so

# ---------------------------------------------------------------------------
# Sprint 5.3: PGO + BOLT pipeline (per phase doc Deliverables block).
#
# Stage 1: PGO instrumented build. Compile with
# `-fprofile-generate=$(abspath $(PGO_DIR))` so the resulting .so
# emits per-edge profile data when exercised by the training run.
pgo-bench-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) -DMCTS_IMPERATIVE_INSTRUMENTED=0 $(LDFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative_bench.so

pgo-instr-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) -DMCTS_IMPERATIVE_INSTRUMENTED=1 $(LDFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative_instrumented.so

# Stage 2: PGO optimized rebuild. Compile with
# `-fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction` so
# the optimizer pulls the recorded edge frequencies into hot-path
# layout decisions.
pgo-bench-use:
	mkdir -p build
	@if ! find $(PGO_DIR) -type f -name '*.gcda' -size +0c -print -quit | grep -q .; then \
	  find . -type f \( -name '*.gcda' -o -name '*.gcno' -o -name '*gcov*' \) -print | sort | head -100 >&2; \
	  echo "[pgo] no non-empty .gcda files under $(PGO_DIR); failing mandatory PGO build" >&2; \
	  exit 1; \
	fi
	$(CXX) $(CXXFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction -DMCTS_IMPERATIVE_INSTRUMENTED=0 $(LDFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_bench.so

pgo-instr-use:
	mkdir -p build
	@if ! find $(PGO_DIR) -type f -name '*.gcda' -size +0c -print -quit | grep -q .; then \
	  find . -type f \( -name '*.gcda' -o -name '*.gcno' -o -name '*gcov*' \) -print | sort | head -100 >&2; \
	  echo "[pgo] no non-empty .gcda files under $(PGO_DIR); failing mandatory PGO build" >&2; \
	  exit 1; \
	fi
	$(CXX) $(CXXFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction -DMCTS_IMPERATIVE_INSTRUMENTED=1 $(LDFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_imperative_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_instrumented.so

# Stage 3 (BOLT): instrument the PGO-optimized shared library with
# `llvm-bolt -instrument` so a fresh training run writes a
# `.fdata` BOLT profile. perf is not required in the doctrine pipeline
# because BOLT's `-instrument` mode self-records.
bolt-bench-instrument:
	mkdir -p $(BOLT_DIR)
	llvm-bolt build/libmcts_cpp_imperative_bench.so -instrument \
	    -o build/libmcts_cpp_imperative_bench.inst.so \
	    --instrumentation-file=$(abspath $(BOLT_DIR))/bench.fdata \
	    --instrumentation-file-append-pid
	test -s build/libmcts_cpp_imperative_bench.inst.so

bolt-instr-instrument:
	mkdir -p $(BOLT_DIR)
	llvm-bolt build/libmcts_cpp_imperative_instrumented.so -instrument \
	    -o build/libmcts_cpp_imperative_instrumented.inst.so \
	    --instrumentation-file=$(abspath $(BOLT_DIR))/instr.fdata \
	    --instrumentation-file-append-pid
	test -s build/libmcts_cpp_imperative_instrumented.inst.so

# Stage 4: BOLT optimize. Read the BOLT profile and produce the
# post-link reordered `.bolted.so`. The doctrine reorder choice is
# `ext-tsp` (the cache-aware extension to TSP block layout).
bolt-bench-optimize:
	@fdata=""; \
	for candidate in $$(ls -t $(BOLT_DIR)/bench.fdata* 2>/dev/null); do \
	  if [ -s "$$candidate" ]; then fdata="$$candidate"; break; fi; \
	done; \
	if [ -z "$$fdata" ]; then \
	  echo "[bolt] no usable bench.fdata; failing mandatory BOLT build" >&2; \
	  exit 1; \
	fi; \
	llvm-bolt build/libmcts_cpp_imperative_bench.so \
	    -o build/libmcts_cpp_imperative_bench.bolted.so \
	    -data $$fdata -reorder-blocks=ext-tsp; \
	test -s build/libmcts_cpp_imperative_bench.bolted.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_bench.bolted.so

bolt-instr-optimize:
	@fdata=""; \
	for candidate in $$(ls -t $(BOLT_DIR)/instr.fdata* 2>/dev/null); do \
	  if [ -s "$$candidate" ]; then fdata="$$candidate"; break; fi; \
	done; \
	if [ -z "$$fdata" ]; then \
	  echo "[bolt] no usable instr.fdata; failing mandatory BOLT build" >&2; \
	  exit 1; \
	fi; \
	llvm-bolt build/libmcts_cpp_imperative_instrumented.so \
	    -o build/libmcts_cpp_imperative_instrumented.bolted.so \
	    -data $$fdata -reorder-blocks=ext-tsp; \
	test -s build/libmcts_cpp_imperative_instrumented.bolted.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_instrumented.bolted.so

# Stage 5 (install): rename `_bench.bolted.so` to the canonical FFI
# load name `libmcts_cpp_imperative.so`. `_instrumented.bolted.so`
# keeps its full name and is symlinked to the canonical instrumented
# load name (loaded by `mcts verify`, `mcts play`, `mcts inspect replay`).
install-bench:
	cp build/libmcts_cpp_imperative_bench.bolted.so build/libmcts_cpp_imperative.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative.so
	cp build/libmcts_cpp_imperative_instrumented.bolted.so build/libmcts_cpp_imperative_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_imperative_instrumented.so

# Post-link engine_build_id patch (mirrors the cpp-legacy target).
envelope-build-id:
	@objcopy_tool=$$(command -v llvm-objcopy-19 || command -v llvm-objcopy || command -v objcopy || true); \
	if [ -n "$$objcopy_tool" ] && [ -n "$(LIB)" ]; then \
		sha=$$(sha256sum $(LIB) | cut -c1-64); \
		python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))" "$$sha" \
			> $(LIB).envelope.bin; \
		"$$objcopy_tool" --update-section .envelope_build_id=$(LIB).envelope.bin \
			$(LIB); \
		rm -f $(LIB).envelope.bin; \
	fi

clean:
	rm -rf build $(PGO_DIR) $(BOLT_DIR)
