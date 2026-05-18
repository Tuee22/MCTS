# rust

Backend (iv) Rust `cdylib`. The crate uses the planned module topology, installs
`mimalloc::MiMalloc` as the global allocator, stamps `rustc --version` into the
exported engine envelope through `build.rs`, and exposes the visit-vector,
recompute, and cached `read_visits` C ABI hooks.

The remaining Rust development-plan work is the canonical PGO+BOLT install
closure and the amd64 verdict for the BOLT post-link step.
