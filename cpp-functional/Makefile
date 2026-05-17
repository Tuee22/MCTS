.PHONY: smoke all clean envelope-build-id bench instrumented \
        pgo-bench-generate pgo-instr-generate pgo-bench-use pgo-instr-use \
        bolt-bench-instrument bolt-instr-instrument \
        bolt-bench-optimize bolt-instr-optimize install-bench

CXX ?= g++
# Doctrine flag set shared with backend (ii) so the (ii)-vs-(iii)
# comparison isolates style as the variable. Sprint 5.3 closure:
# `-fno-exceptions` is now enabled — the legacy `throw std::string(...)`
# paths in `board.cpp` and `mcts.hpp`'s `lexical_cast` were replaced
# with `__builtin_trap()`, and the C ABI shim's defensive
# `try`/`catch (...)` wrappers were removed.
CXXFLAGS ?= -std=c++23 -O3 -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions -fPIC -Wno-pessimizing-move -Iengine
LDFLAGS ?= -shared -flto
LDLIBS ?= -lmimalloc

ENGINE_SRCS = engine/board.cpp engine/search.cpp c-abi/mcts_cpp_functional.cc

PGO_DIR ?= pgo-profile
BOLT_DIR ?= bolt-profile

all: smoke

smoke:
	mkdir -p build
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional.so

bench:
	mkdir -p build
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.so

instrumented:
	mkdir -p build
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.so

# PGO + BOLT pipeline mirroring Sprint 5.3 for backend (ii).
pgo-bench-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(PGO_DIR) $(LDFLAGS) -fprofile-generate=$(PGO_DIR) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.so

pgo-instr-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(PGO_DIR) $(LDFLAGS) -fprofile-generate=$(PGO_DIR) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.so

pgo-bench-use:
	mkdir -p build
	$(CXX) $(CXXFLAGS) -fprofile-use=$(PGO_DIR) -fprofile-correction $(LDFLAGS) -fprofile-use=$(PGO_DIR) -fprofile-correction $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.so

pgo-instr-use:
	mkdir -p build
	$(CXX) $(CXXFLAGS) -fprofile-use=$(PGO_DIR) -fprofile-correction $(LDFLAGS) -fprofile-use=$(PGO_DIR) -fprofile-correction $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.so

bolt-bench-instrument:
	mkdir -p $(BOLT_DIR)
	llvm-bolt build/libmcts_cpp_functional_bench.so -instrument \
	    -o build/libmcts_cpp_functional_bench.inst.so \
	    --instrumentation-file=$(abspath $(BOLT_DIR))/bench.fdata \
	    --instrumentation-file-append-pid 2>/dev/null || \
	  echo "[bolt] bench instrument skipped: $$?"

bolt-instr-instrument:
	mkdir -p $(BOLT_DIR)
	llvm-bolt build/libmcts_cpp_functional_instrumented.so -instrument \
	    -o build/libmcts_cpp_functional_instrumented.inst.so \
	    --instrumentation-file=$(abspath $(BOLT_DIR))/instr.fdata \
	    --instrumentation-file-append-pid 2>/dev/null || \
	  echo "[bolt] instrumented instrument skipped: $$?"

bolt-bench-optimize:
	@if [ -s $(BOLT_DIR)/bench.fdata ] || ls $(BOLT_DIR)/bench.fdata.* >/dev/null 2>&1; then \
	  fdata=$$(ls -t $(BOLT_DIR)/bench.fdata* 2>/dev/null | head -1); \
	  llvm-bolt build/libmcts_cpp_functional_bench.so \
	      -o build/libmcts_cpp_functional_bench.bolted.so \
	      -data $$fdata -reorder-blocks=ext-tsp 2>/dev/null || \
	    cp build/libmcts_cpp_functional_bench.so build/libmcts_cpp_functional_bench.bolted.so; \
	else \
	  echo "[bolt] no bench.fdata; copying PGO output as bolted artefact"; \
	  cp build/libmcts_cpp_functional_bench.so build/libmcts_cpp_functional_bench.bolted.so; \
	fi
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.bolted.so

bolt-instr-optimize:
	@if [ -s $(BOLT_DIR)/instr.fdata ] || ls $(BOLT_DIR)/instr.fdata.* >/dev/null 2>&1; then \
	  fdata=$$(ls -t $(BOLT_DIR)/instr.fdata* 2>/dev/null | head -1); \
	  llvm-bolt build/libmcts_cpp_functional_instrumented.so \
	      -o build/libmcts_cpp_functional_instrumented.bolted.so \
	      -data $$fdata -reorder-blocks=ext-tsp 2>/dev/null || \
	    cp build/libmcts_cpp_functional_instrumented.so build/libmcts_cpp_functional_instrumented.bolted.so; \
	else \
	  echo "[bolt] no instr.fdata; copying PGO output as bolted artefact"; \
	  cp build/libmcts_cpp_functional_instrumented.so build/libmcts_cpp_functional_instrumented.bolted.so; \
	fi
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.bolted.so

install-bench:
	cp build/libmcts_cpp_functional_bench.bolted.so build/libmcts_cpp_functional.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional.so
	cp build/libmcts_cpp_functional_instrumented.bolted.so build/libmcts_cpp_functional_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.so

envelope-build-id:
	@if command -v objcopy >/dev/null 2>&1 && [ -n "$(LIB)" ]; then \
		sha=$$(sha256sum $(LIB) | cut -c1-64); \
		python3 -c "import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))" "$$sha" \
			> $(LIB).envelope.bin; \
		objcopy --update-section .envelope_build_id=$(LIB).envelope.bin \
			$(LIB) 2>/dev/null || true; \
	fi

clean:
	rm -rf build $(PGO_DIR) $(BOLT_DIR)
