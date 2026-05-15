mod board;
mod c_abi;
mod envelope;
mod rollout;
mod search;
mod tree;

#[global_allocator]
static GLOBAL_ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;
