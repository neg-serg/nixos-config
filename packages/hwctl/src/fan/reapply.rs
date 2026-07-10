use anyhow::Result;
use std::process::Command;

/// Post-resume hook: re-enable manual PWM control and restart fancontrol.
///
/// Mirrors the shell script `fancontrol-reapply.sh`.
pub fn run_reapply(include_gpu: bool) -> Result<()> {
    // Re-enable manual mode for all Nuvoton PWM channels
    for dev in crate::hwmon::HwmonDevice::discover()? {
        if dev.is_nuvoton() {
            for ch in dev.pwm_channels() {
                let _ = dev.set_manual(ch);
            }
        }
    }

    // Optionally re-enable AMDGPU pwm1
    if include_gpu {
        for dev in crate::hwmon::HwmonDevice::discover()? {
            if dev.is_amdgpu() {
                if let Ok(_) = dev.set_manual(1) {
                    // succeeded
                }
            }
        }
    }

    // Nudge fancontrol in case device state changed
    let _ = Command::new("systemctl")
        .args(["try-restart", "fancontrol.service"])
        .output();

    Ok(())
}
