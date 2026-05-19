# rust

Backend (iv) Rust `cdylib`. The crate uses the planned module topology, installs
`mimalloc::MiMalloc` as the global allocator, stamps `rustc --version` into the
exported engine envelope through `build.rs`, and exposes the visit-vector,
recompute, and cached `read_visits` C ABI hooks.

The Phase 6 Rust install surface is closed: `mcts build rust` drives PGO
train/merge/use, BOLT training/install on amd64, canonical
`rust/target/release/libmcts_rust.so` publication, and post-link
`engine_build_id` patching through the Compose entrypoint.
