use anyhow::Result;
use std::time::Duration;

/// Flags for the test-stop subcommand.
#[derive(Debug, Clone, Default)]
pub struct TestFlags {
    pub include_cpu: bool,
    pub device: Option<String>,
    pub wait_secs: u64,
    pub threshold: u32,
    pub list_only: bool,
}

pub fn run_test_stop(flags: TestFlags) -> Result<()> {
    require_root()?;

    let wait = if flags.wait_secs > 0 {
        flags.wait_secs
    } else {
        6
    };
    let threshold = if flags.threshold > 0 {
        flags.threshold
    } else {
        50
    };

    // Warn if fancontrol is active
    let fanctl_active = is_fancontrol_active();
    if fanctl_active {
        eprintln!("[!] fancontrol.service is active; it may fight this test.");
    }

    // Find target devices
    let devices: Vec<crate::hwmon::HwmonDevice> = if let Some(ref target) = flags.device {
        let all = crate::hwmon::HwmonDevice::discover()?;
        let matched: Vec<_> = all
            .into_iter()
            .filter(|d| {
                d.basename() == *target
                    || d.name == *target
                    || d.path.to_string_lossy().as_ref() == target.as_str()
            })
            .collect();
        if matched.is_empty() {
            anyhow::bail!("device not found: {target}");
        }
        matched
    } else {
        crate::hwmon::HwmonDevice::discover()?
            .into_iter()
            .filter(|d| d.is_nuvoton())
            .collect()
    };

    if devices.is_empty() {
        anyhow::bail!("no nct* hwmon device found");
    }

    for dev in &devices {
        println!("Device: {} (name: {})", dev.path.display(), dev.name);
        list_channels(dev);
        if flags.list_only {
            continue;
        }
        for ch in dev.pwm_channels() {
            let lbl = dev.fan_label(ch).unwrap_or_default();
            test_channel(dev, ch, &lbl, flags.include_cpu, wait, threshold)?;
        }
        println!();
    }

    if fanctl_active {
        eprintln!("[!] fancontrol.service was active. If results look odd, rerun with the service stopped.");
    }
    Ok(())
}

fn list_channels(dev: &crate::hwmon::HwmonDevice) {
    for ch in dev.pwm_channels() {
        let lbl = dev.fan_label(ch).unwrap_or_else(|| "no-label".to_string());
        let fin = if dev.fan_input_exists(ch) {
            format!(" -> fan{ch}")
        } else {
            String::new()
        };
        println!("  - pwm{ch} ({lbl}){fin}");
    }
}

fn test_channel(
    dev: &crate::hwmon::HwmonDevice,
    ch: u8,
    label: &str,
    include_cpu: bool,
    wait_secs: u64,
    threshold: u32,
) -> Result<()> {
    let pwm_enable_path = dev.path.join(format!("pwm{}_enable", ch));
    if !pwm_enable_path.exists() {
        eprintln!("  [!] pwm{ch}_enable: missing, skipping");
        return Ok(());
    }

    let fan_path = dev.path.join(format!("fan{}_input", ch));
    if !fan_path.exists() {
        eprintln!("  [!] fan{ch}_input: missing, skipping");
        return Ok(());
    }

    // Skip CPU/PUMP/AIO-like channels unless asked
    if !include_cpu {
        let lower = label.to_lowercase();
        if lower.contains("cpu")
            || lower.contains("pump")
            || lower.contains("aio")
            || lower.contains("opt")
            || lower.contains("pch")
        {
            println!("  [i] pwm{ch}: skipping CPU/PUMP-labeled channel ('{label}')");
            return Ok(());
        }
    }

    let orig_enable = dev.read_pwm_enable(ch).unwrap_or(2);
    let orig_pwm = dev.read_pwm(ch).unwrap_or(0);
    let base_rpm = dev.read_fan_rpm(ch).unwrap_or(0);

    println!(
        "  [i] pwm{ch} ('{label}'): baseline {base_rpm} RPM; testing 0%"
    );

    // Set manual mode
    if dev.set_manual(ch).is_err() {
        eprintln!("  [!] pwm{ch}: cannot set manual mode, skipping");
        return Ok(());
    }

    // Set PWM to 0
    if dev.write_pwm(ch, 0).is_err() {
        eprintln!("  [!] pwm{ch}: write 0 failed (HW clamp?), skipping");
        let _ = dev.write_pwm(ch, orig_pwm);
        let _ = dev.set_pwm_mode(ch, orig_enable);
        return Ok(());
    }

    // Wait
    std::thread::sleep(Duration::from_secs(wait_secs));

    let stop_rpm = dev.read_fan_rpm(ch).unwrap_or(0);
    let new_pwm = dev.read_pwm(ch).unwrap_or(0);

    // Restore
    let _ = dev.write_pwm(ch, orig_pwm);
    let _ = dev.set_pwm_mode(ch, orig_enable);

    if new_pwm != 0 {
        println!("    result: NOT SUPPORTED (controller clamped PWM to {new_pwm})");
    } else if stop_rpm <= threshold {
        println!("    result: SUPPORTED (RPM {stop_rpm} <= {threshold})");
    } else {
        println!("    result: NOT SUPPORTED (RPM stayed at {stop_rpm} > {threshold})");
    }

    Ok(())
}

fn is_fancontrol_active() -> bool {
    std::process::Command::new("systemctl")
        .args(["is-active", "--quiet", "fancontrol"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn require_root() -> Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        anyhow::bail!("must be root to test fan stop (try: sudo hwctl fan test-stop)");
    }
    Ok(())
}
