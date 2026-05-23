# rust

Backend (iv) Rust `cdylib`. The crate uses the planned module topology, installs
the local `SystemMiMalloc` wrapper over the container's system `libmimalloc` as
the global allocator, stamps `rustc --version` into the exported engine envelope
through `build.rs`, and exposes the visit-vector, recompute, and cached
`read_visits` C ABI hooks.

The Phase 6 Rust install surface is closed: `mcts build rust` drives PGO
train/merge/use with `-C target-cpu=native -C link-arg=-fuse-ld=lld
-C link-arg=-Wl,--emit-relocs`, BOLT training/install on amd64, LLVM `objcopy`
post-link `engine_build_id` patching, canonical
`rust/target/release/libmcts_rust.so` publication, and a final installed-cdylib
smoke through the Compose entrypoint. Missing PGO data, missing BOLT `.fdata`,
a missing bolted cdylib, or a failed installed smoke is a build failure; the
Rust surface does not install PGO-only or unoptimized fallback artefacts.
