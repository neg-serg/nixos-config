use anyhow::{Context, Result};
use std::process::Command;

/// Set all CPU/case fans to a fixed PWM value.
///
/// Channels used: 1, 4, 5, 6, 7 (GPU channels 2, 3 are skipped with a warning).
pub fn run_manual(pwm_value: Option<u8>) -> Result<()> {
    require_root()?;
    let target = pwm_value.unwrap_or(70);

    // Find nct6799 hwmon
    let nct = crate::hwmon::HwmonDevice::find_nuvoton()?
        .ok_or_else(|| anyhow::anyhow!("nct6799 hardware monitor not found"))?;
    println!("Found Nuvoton at {}", nct.path.display());

    // Stop fancontrol
    println!("Stopping fancontrol service...");
    let status = Command::new("systemctl")
        .args(["stop", "fancontrol"])
        .status()
        .context("failed to stop fancontrol")?;
    if !status.success() {
        eprintln!("Warning: systemctl stop fancontrol returned non-zero (may not be running)");
    }

    // PWM channels for CPU/Case fans: 1, 4, 5, 6, 7
    // GPU channels 2, 3 are skipped
    let channels = [1u8, 4, 5, 6, 7];
    println!("Setting CPU/Case fans to PWM {target}...");

    for &ch in &channels {
        let pwm_path = nct.path.join(format!("pwm{}_enable", ch));
        if !pwm_path.exists() {
            println!("  Warning: pwm{}_enable not found, skipping.", ch);
            continue;
        }
        nct.set_manual(ch)?;
        nct.write_pwm(ch, target)?;
        println!("  Set pwm{ch} to {target}");
    }

    println!("Done.");
    println!("WARNING: GPU fans (pwm2, pwm3) are now unmanaged and locked at their last speed!");
    println!("Run 'hwctl fan auto' to restore automatic control.");
    Ok(())
}

fn require_root() -> Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        anyhow::bail!("must be root to control fans (try: sudo hwctl fan manual)");
    }
    Ok(())
}
