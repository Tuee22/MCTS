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
LDFLAGS ?= -shared -flto -Wl,--emit-relocs
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
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(LDFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so

pgo-instr-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(LDFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so

pgo-bench-use:
	mkdir -p build
	@if ! find $(PGO_DIR) -type f -name '*.gcda' -size +0c -print -quit | grep -q .; then \
	  find . -type f \( -name '*.gcda' -o -name '*.gcno' -o -name '*gcov*' \) -print | sort | head -100 >&2; \
	  echo "[pgo] no non-empty .gcda files under $(PGO_DIR); failing mandatory PGO build" >&2; \
	  exit 1; \
	fi
	$(CXX) $(CXXFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction $(LDFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.so

pgo-instr-use:
	mkdir -p build
	@if ! find $(PGO_DIR) -type f -name '*.gcda' -size +0c -print -quit | grep -q .; then \
	  find . -type f \( -name '*.gcda' -o -name '*.gcno' -o -name '*gcov*' \) -print | sort | head -100 >&2; \
	  echo "[pgo] no non-empty .gcda files under $(PGO_DIR); failing mandatory PGO build" >&2; \
	  exit 1; \
	fi
	$(CXX) $(CXXFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction $(LDFLAGS) -fprofile-use=$(abspath $(PGO_DIR)) -fprofile-correction $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.so

bolt-bench-instrument:
	mkdir -p $(BOLT_DIR)
	llvm-bolt build/libmcts_cpp_functional_bench.so -instrument \
	    -o build/libmcts_cpp_functional_bench.inst.so \
	    --instrumentation-file=$(abspath $(BOLT_DIR))/bench.fdata \
	    --instrumentation-file-append-pid
	test -s build/libmcts_cpp_functional_bench.inst.so

bolt-instr-instrument:
	mkdir -p $(BOLT_DIR)
	llvm-bolt build/libmcts_cpp_functional_instrumented.so -instrument \
	    -o build/libmcts_cpp_functional_instrumented.inst.so \
	    --instrumentation-file=$(abspath $(BOLT_DIR))/instr.fdata \
	    --instrumentation-file-append-pid
	test -s build/libmcts_cpp_functional_instrumented.inst.so

bolt-bench-optimize:
	@fdata=""; \
	for candidate in $$(ls -t $(BOLT_DIR)/bench.fdata* 2>/dev/null); do \
	  if [ -s "$$candidate" ]; then fdata="$$candidate"; break; fi; \
	done; \
	if [ -z "$$fdata" ]; then \
	  echo "[bolt] no usable bench.fdata; failing mandatory BOLT build" >&2; \
	  exit 1; \
	fi; \
	llvm-bolt build/libmcts_cpp_functional_bench.so \
	    -o build/libmcts_cpp_functional_bench.bolted.so \
	    -data $$fdata -reorder-blocks=ext-tsp; \
	test -s build/libmcts_cpp_functional_bench.bolted.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.bolted.so

bolt-instr-optimize:
	@fdata=""; \
	for candidate in $$(ls -t $(BOLT_DIR)/instr.fdata* 2>/dev/null); do \
	  if [ -s "$$candidate" ]; then fdata="$$candidate"; break; fi; \
	done; \
	if [ -z "$$fdata" ]; then \
	  echo "[bolt] no usable instr.fdata; failing mandatory BOLT build" >&2; \
	  exit 1; \
	fi; \
	llvm-bolt build/libmcts_cpp_functional_instrumented.so \
	    -o build/libmcts_cpp_functional_instrumented.bolted.so \
	    -data $$fdata -reorder-blocks=ext-tsp; \
	test -s build/libmcts_cpp_functional_instrumented.bolted.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.bolted.so

install-bench:
	cp build/libmcts_cpp_functional_bench.bolted.so build/libmcts_cpp_functional.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional.so
	cp build/libmcts_cpp_functional_instrumented.bolted.so build/libmcts_cpp_functional_instrumented.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_instrumented.so

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
