.PHONY: smoke all clean envelope-build-id bench instrumented \
        pgo-bench-generate pgo-instr-generate pgo-bench-use pgo-instr-use \
        pgo-merge \
        bolt-bench-instrument bolt-instr-instrument \
        bolt-bench-optimize bolt-instr-optimize install-bench

# Sprint 6.11: backend (iii) cpp-functional pivoted from g++ to
# clang++-19 to match backend (ii) (Sprint 5.9) and complete the
# functional-cohort compiler-stack alignment. The functional-core source
# style is unchanged; only the build harness flips. `:=` (not `?=`) so
# the Dockerfile's `ENV CXX=g++` cannot silently override; a
# command-line `make CXX=...` still wins per GNU make's variable
# precedence rules.
CXX := clang++-19
LLVM_PROFDATA := llvm-profdata-19
# Doctrine flag set shared with backend (ii) so the (ii)-vs-(iii)
# comparison isolates source style as the variable. Backend (iii)'s
# compact functional-core state is header-only; the old legacy
# `corridors::board` translation unit is no longer part of this build.
# Sprint 6.9 adopts the Sprint 5.8 backend (ii) flag scrub:
#   -fno-stack-protector — engine core takes no untrusted input on the
#                          hot path; SSP cookie is dead weight.
#   -fno-rtti           — no `dynamic_cast` or `typeid` on the hot path.
# Sprint 6.11: `-fipa-pta` is dropped because clang rejects the flag
# (GCC-only inter-procedural points-to analysis); the Sprint 5.9 audit
# showed it was not load-bearing on the (ii) baseline either way.
CXXFLAGS ?= -std=c++23 -O3 -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions -fno-stack-protector -fno-rtti -fPIC -Wno-pessimizing-move -Iengine
LDFLAGS ?= -shared -flto -Wl,--emit-relocs -fuse-ld=lld
LDLIBS ?= -lmimalloc

ENGINE_SRCS = engine/search.cpp c-abi/mcts_cpp_functional.cc

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

# PGO + BOLT pipeline mirroring Sprint 5.3 for backend (ii). Sprint 6.11
# rewrote the PGO half from GCC `.gcda` (`-fprofile-correction` etc.) to
# LLVM `.profraw` → merged `.profdata` consumed via `-fprofile-use=<file>`,
# mirroring cpp-imperative's Sprint 5.9 pivot.
pgo-bench-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(LDFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so

pgo-instr-generate:
	mkdir -p build $(PGO_DIR)
	$(CXX) $(CXXFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(LDFLAGS) -fprofile-generate=$(abspath $(PGO_DIR)) $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so

# Sprint 6.11: merge clang's raw `.profraw` files into a single
# `.profdata` consumed by `-fprofile-use=<file>`. Mirrors cpp-imperative
# and the Rust PGO pipeline. The orchestrator (`src/MCTS/CLI/Build.hs`
# → `cppPgoBoltPlan`) runs the training workload between
# `pgo-{bench,instr}-generate` and this merge, then `pgo-{bench,instr}-use`.
pgo-merge:
	@profraw_files=$$(find $(PGO_DIR) -type f -name '*.profraw' -size +0c -print | sort); \
	if [ -z "$$profraw_files" ]; then \
	  find $(PGO_DIR) -type f -print | sort | head -100 >&2; \
	  echo "[pgo] no non-empty .profraw files under $(PGO_DIR); failing mandatory PGO build" >&2; \
	  exit 1; \
	fi; \
	$(LLVM_PROFDATA) merge -o $(PGO_DIR)/default.profdata $$profraw_files; \
	test -s $(PGO_DIR)/default.profdata

pgo-bench-use:
	mkdir -p build
	@if [ ! -s $(PGO_DIR)/default.profdata ]; then \
	  echo "[pgo] $(PGO_DIR)/default.profdata missing or empty; run pgo-merge first" >&2; \
	  exit 1; \
	fi
	$(CXX) $(CXXFLAGS) -fprofile-use=$(abspath $(PGO_DIR))/default.profdata $(LDFLAGS) -fprofile-use=$(abspath $(PGO_DIR))/default.profdata $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_bench.so
	$(MAKE) envelope-build-id LIB=build/libmcts_cpp_functional_bench.so

pgo-instr-use:
	mkdir -p build
	@if [ ! -s $(PGO_DIR)/default.profdata ]; then \
	  echo "[pgo] $(PGO_DIR)/default.profdata missing or empty; run pgo-merge first" >&2; \
	  exit 1; \
	fi
	$(CXX) $(CXXFLAGS) -fprofile-use=$(abspath $(PGO_DIR))/default.profdata $(LDFLAGS) -fprofile-use=$(abspath $(PGO_DIR))/default.profdata $(ENGINE_SRCS) $(LDLIBS) -o build/libmcts_cpp_functional_instrumented.so
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
	    -data $$fdata \
	    -reorder-blocks=ext-tsp \
	    -split-functions -split-strategy=cdsplit \
	    -reorder-functions=cdsort \
	    -icf=1; \
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
	    -data $$fdata \
	    -reorder-blocks=ext-tsp \
	    -split-functions -split-strategy=cdsplit \
	    -reorder-functions=cdsort \
	    -icf=1; \
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
