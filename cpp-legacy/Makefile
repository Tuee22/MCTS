.PHONY: smoke all clean

all: smoke

smoke:
	mkdir -p build
	$(CXX) -std=c++17 -O3 -fPIC -Wall -Wno-pessimizing-move -Ilegacy-core -shared \
		legacy-core/board.cpp c-abi/mcts_cpp_legacy.cc c-abi/rng.cc \
		-o build/libmcts_cpp_legacy.so

clean:
	rm -rf build
