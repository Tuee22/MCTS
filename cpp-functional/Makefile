.PHONY: smoke all clean

CXX ?= g++
CXXFLAGS ?= -std=c++23 -O3 -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions -fPIC
LDFLAGS ?= -shared -flto
LDLIBS ?= -lmimalloc

all: smoke

smoke:
	mkdir -p build
	$(CXX) $(CXXFLAGS) $(LDFLAGS) c-abi/mcts_cpp_functional.cc $(LDLIBS) -o build/libmcts_cpp_functional.so

clean:
	rm -rf build
