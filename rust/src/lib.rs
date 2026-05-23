mod allocator;
mod board;
mod c_abi;
mod envelope;
mod rollout;
mod search;
mod tree;
mod xoshiro256pp;

#[global_allocator]
static GLOBAL_ALLOCATOR: allocator::SystemMiMalloc = allocator::SystemMiMalloc;
