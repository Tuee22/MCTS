.PHONY: smoke all clean

all: smoke

smoke:
	mkdir -p build
	$(CXX) -std=c++23 -O3 -fPIC -shared c-abi/mcts_cpp_imperative.cc -o build/libmcts_cpp_imperative.so

clean:
	rm -rf build
