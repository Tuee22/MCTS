use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=MCTS_GIT_COMMIT");
    println!("cargo:rustc-link-lib=mimalloc");

    let version = Command::new("rustc")
        .arg("--version")
        .output()
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|raw| raw.trim().to_owned())
        .filter(|raw| !raw.is_empty())
        .unwrap_or_else(|| "rustc unknown".to_owned());

    println!("cargo:rustc-env=MCTS_RUSTC_VERSION={version}");
}
