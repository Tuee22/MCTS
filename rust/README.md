# rust

Backend (iv) Rust smoke `cdylib`. The crate already uses the planned module
topology, installs `mimalloc::MiMalloc` as the global allocator, and stamps
`rustc --version` into the exported engine envelope through `build.rs`.

The real Rust engine and the rustc PGO+BOLT build pipeline remain active
development-plan work.
