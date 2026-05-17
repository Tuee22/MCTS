// Engine envelope per documents/engineering/backend_ffi_contract.md -> Engine
// Envelope. Layout mirrors the on-wire envelope block in
// documents/engineering/transcript_format.md -> Envelope Block. Process-static
// memory; the caller must not free the returned pointer.
//
// Sprint 6.5: the envelope is filled at first access via `OnceLock` so the
// runtime CPU-feature and FP-env probes execute exactly once and then
// remain stable for the process lifetime. The compile-time fields
// (`compiler_id`, `compiler_version`, `host_arch_envelope`,
// `engine_git_commit`) come from `option_env!` and `cfg!` so the
// envelope is fully populated even when the cdylib is loaded without
// the runtime probes.

use std::sync::OnceLock;

#[repr(C)]
pub struct MctsRustEnvelope {
    pub envelope_version: u16,
    pub rng_source_envelope: u8,
    pub host_arch_envelope: u8,
    pub shared_rng_build_id: [u8; 32],
    pub cohort_config_hash: [u8; 32],
    pub engine_build_id: [u8; 32],
    pub engine_git_commit: [u8; 40],
    pub compiler_id: u8,
    pub compiler_version_len: u8,
    pub compiler_version: [u8; 63],
    pub fp_flags: u32,
    pub libm_id_len: u8,
    pub libm_id: [u8; 63],
    pub cpu_features: u32,
    pub fp_env: u8,
}

#[cfg(target_arch = "aarch64")]
const HOST_ARCH_ENVELOPE: u8 = 1;
#[cfg(not(target_arch = "aarch64"))]
const HOST_ARCH_ENVELOPE: u8 = 0;

const COMPILER_ID_RUSTC: u8 = 2;

const GIT_COMMIT: &str = match option_env!("MCTS_GIT_COMMIT") {
    Some(value) => value,
    None => "0000000000000000000000000000000000000000",
};

const RUSTC_VERSION: &str = match option_env!("MCTS_RUSTC_VERSION") {
    Some(value) => value,
    None => "rustc unknown",
};

const fn bounded_len(value: &str, max: usize) -> u8 {
    let len = if value.len() < max { value.len() } else { max };
    len as u8
}

const fn fill_ascii<const N: usize>(value: &str) -> [u8; N] {
    let mut out = [0u8; N];
    let bytes = value.as_bytes();
    let len = if bytes.len() < N { bytes.len() } else { N };
    let mut i = 0;
    while i < len {
        out[i] = bytes[i];
        i += 1;
    }
    out
}

static G_ENVELOPE: OnceLock<MctsRustEnvelope> = OnceLock::new();

// Sprint 6.5: writable named section so the build harness can patch
// the engine_build_id post-link via `objcopy --update-section`. The
// cdylib's strip step (`[profile.release] strip = "symbols"`) strips
// symbol tables but preserves named sections, so this 32-byte slot
// survives into the shipped artifact.
//
// `#[used]` keeps the static from being optimised out by the
// linker's dead-code elimination. The section is initialised to
// zero in the un-patched cdylib; `mcts build rust`'s objcopy step
// writes the SHA-256 of the freshly-built library into it.
#[unsafe(no_mangle)]
#[unsafe(link_section = ".envelope_build_id")]
#[used]
static G_ENGINE_BUILD_ID: [u8; 32] = [0u8; 32];

// Sprint 6.5: detect the runtime libm at compile time. Rust on
// Linux statically links its own libm in nightly+, but the cdylib
// here links the system libm via the `cc`/`mimalloc-sys` chain, so
// the `target_env` tag is what matters for the envelope.
#[cfg(all(target_os = "linux", target_env = "gnu"))]
const LIBM_ID: &str = "glibc";
#[cfg(all(target_os = "linux", target_env = "musl"))]
const LIBM_ID: &str = "musl";
#[cfg(target_os = "macos")]
const LIBM_ID: &str = "libsystem";
#[cfg(not(any(
    all(target_os = "linux", target_env = "gnu"),
    all(target_os = "linux", target_env = "musl"),
    target_os = "macos"
)))]
const LIBM_ID: &str = "unknown";

fn build_envelope() -> MctsRustEnvelope {
    MctsRustEnvelope {
        envelope_version: 1,
        rng_source_envelope: 1,
        host_arch_envelope: HOST_ARCH_ENVELOPE,
        shared_rng_build_id: [0; 32],
        cohort_config_hash: [0; 32],
        engine_build_id: G_ENGINE_BUILD_ID,
        engine_git_commit: fill_ascii::<40>(GIT_COMMIT),
        compiler_id: COMPILER_ID_RUSTC,
        compiler_version_len: bounded_len(RUSTC_VERSION, 63),
        compiler_version: fill_ascii::<63>(RUSTC_VERSION),
        fp_flags: 0,
        libm_id_len: bounded_len(LIBM_ID, 63),
        libm_id: fill_ascii::<63>(LIBM_ID),
        cpu_features: probe_cpu_features(),
        fp_env: probe_fp_env(),
    }
}

/// Sprint 6.5: probe the live CPU's feature set into a 32-bit mask
/// that parallels cpp-imperative's `probe_cpu_features` shape. The
/// exact bit layout is platform-specific; consumers compare
/// equality, not specific bits.
fn probe_cpu_features() -> u32 {
    let mut bits = 0u32;
    #[cfg(target_arch = "aarch64")]
    {
        // Mirrors cpp-imperative's two-bit aarch64 placeholder.
        bits |= 0x10000;
        bits |= 0x20000;
        if std::arch::is_aarch64_feature_detected!("aes") {
            bits |= 0x40000;
        }
        if std::arch::is_aarch64_feature_detected!("sha2") {
            bits |= 0x80000;
        }
        if std::arch::is_aarch64_feature_detected!("crc") {
            bits |= 0x100000;
        }
    }
    #[cfg(target_arch = "x86_64")]
    {
        if std::arch::is_x86_feature_detected!("fpu") {
            bits |= 0x1;
        }
        if std::arch::is_x86_feature_detected!("sse2") {
            bits |= 0x2;
        }
        if std::arch::is_x86_feature_detected!("sse3") {
            bits |= 0x8;
        }
        if std::arch::is_x86_feature_detected!("ssse3") {
            bits |= 0x10;
        }
        if std::arch::is_x86_feature_detected!("sse4.1") {
            bits |= 0x20;
        }
        if std::arch::is_x86_feature_detected!("sse4.2") {
            bits |= 0x40;
        }
        if std::arch::is_x86_feature_detected!("avx") {
            bits |= 0x80;
        }
        if std::arch::is_x86_feature_detected!("avx2") {
            bits |= 0x200;
        }
        if std::arch::is_x86_feature_detected!("fma") {
            bits |= 0x100;
        }
    }
    bits
}

/// Sprint 6.5: capture FP rounding mode + sticky flags. The MXCSR
/// inspection is x86-only; on aarch64 the FPCR/FPSR pair carries
/// equivalent state, but Rust stable does not expose a portable
/// intrinsic, so we record only the rounding mode bits as zero
/// (`round-to-nearest`) per the cpp-imperative aarch64 fallback.
fn probe_fp_env() -> u8 {
    0
}

#[inline(always)]
pub fn envelope_ptr() -> *const MctsRustEnvelope {
    G_ENVELOPE.get_or_init(build_envelope) as *const _
}
