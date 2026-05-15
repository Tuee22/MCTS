// Engine envelope per documents/engineering/backend_ffi_contract.md -> Engine
// Envelope. Layout mirrors the on-wire envelope block in
// documents/engineering/transcript_format.md -> Envelope Block. Process-static
// memory; the caller must not free the returned pointer.
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

static G_ENVELOPE: MctsRustEnvelope = MctsRustEnvelope {
    envelope_version: 1,
    rng_source_envelope: 1,
    host_arch_envelope: HOST_ARCH_ENVELOPE,
    shared_rng_build_id: [0; 32],
    cohort_config_hash: [0; 32],
    engine_build_id: [0; 32],
    engine_git_commit: fill_ascii::<40>(GIT_COMMIT),
    compiler_id: COMPILER_ID_RUSTC,
    compiler_version_len: bounded_len(RUSTC_VERSION, 63),
    compiler_version: fill_ascii::<63>(RUSTC_VERSION),
    fp_flags: 0,
    libm_id_len: 0,
    libm_id: [0; 63],
    cpu_features: 0,
    fp_env: 0,
};

#[inline(always)]
pub fn envelope_ptr() -> *const MctsRustEnvelope {
    &G_ENVELOPE
}
