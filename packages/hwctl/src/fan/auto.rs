use anyhow::{Context, Result};
use std::process::Command;

/// Restart the fancontrol service (automatic fan curve).
pub fn run_auto() -> Result<()> {
    require_root()?;
    println!("Restarting fancontrol service...");
    let status = Command::new("systemctl")
        .args(["restart", "fancontrol"])
        .status()
        .context("failed to run systemctl restart fancontrol")?;
    if status.success() {
        println!("Automatic fan control restored.");
    } else {
        anyhow::bail!("Failed to restart fancontrol service (exit code: {:?})", status.code());
    }
    Ok(())
}

fn require_root() -> Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        anyhow::bail!("must be root to control fans (try: sudo hwctl fan auto)");
    }
    Ok(())
}
