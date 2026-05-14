#[repr(C)]
pub struct MctsRustBoard {
    ply: u16,
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_new_board() -> *mut MctsRustBoard {
    Box::into_raw(Box::new(MctsRustBoard { ply: 0 }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_free_board(board: *mut MctsRustBoard) {
    if !board.is_null() {
        drop(unsafe { Box::from_raw(board) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_is_terminal(board: *const MctsRustBoard) -> i32 {
    if board.is_null() {
        return 1;
    }
    (unsafe { (*board).ply } >= 200) as i32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_select_uct_move(
    board: *mut MctsRustBoard,
    seed: u64,
    sims: u32,
) -> u8 {
    if !board.is_null() {
        unsafe {
            (*board).ply = (*board).ply.saturating_add(1);
        }
    }
    ((seed + sims as u64) % 81) as u8
}

// Engine envelope per documents/engineering/backend_ffi_contract.md → Engine
// Envelope. Layout mirrors the on-wire envelope block in
// documents/engineering/transcript_format.md → Envelope Block. Process-static
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

const fn fill_git_commit() -> [u8; 40] {
    let mut out = [0u8; 40];
    let bytes = GIT_COMMIT.as_bytes();
    let len = if bytes.len() < 40 { bytes.len() } else { 40 };
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
    engine_git_commit: fill_git_commit(),
    compiler_id: COMPILER_ID_RUSTC,
    compiler_version_len: 0,
    compiler_version: [0; 63],
    fp_flags: 0,
    libm_id_len: 0,
    libm_id: [0; 63],
    cpu_features: 0,
    fp_env: 0,
};

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_get_envelope() -> *const MctsRustEnvelope {
    &G_ENVELOPE
}
