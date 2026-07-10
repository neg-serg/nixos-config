use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

/// Flags for the `fan setup` subcommand.
#[derive(Debug, Clone)]
pub struct SetupFlags {
    pub min_temp: u32,
    pub max_temp: u32,
    pub min_pwm: u8,
    pub max_pwm: u8,
    pub allow_stop: bool,
    pub gpu_enable: bool,
    pub gpu_pwm_channels: Vec<u8>,
}

impl Default for SetupFlags {
    fn default() -> Self {
        SetupFlags {
            min_temp: 35,
            max_temp: 75,
            min_pwm: 70,
            max_pwm: 255,
            allow_stop: false,
            gpu_enable: false,
            gpu_pwm_channels: Vec::new(),
        }
    }
}

/// Generate /etc/fancontrol.auto and symlink /etc/fancontrol → /etc/fancontrol.auto.
pub fn run_setup(flags: SetupFlags) -> Result<()> {
    require_root()?;

    // ── Locate Nuvoton hwmon ──
    let nct = crate::hwmon::HwmonDevice::find_nuvoton()?
        .ok_or_else(|| anyhow::anyhow!("no nct6775 hwmon found; skipping"))?;
    let nct_base = nct.basename();

    // ── Locate CPU temperature sensor (k10temp preferred, asusec fallback) ──
    let cpu_dev = crate::hwmon::HwmonDevice::find(|d| d.is_k10temp())?
        .or_else(|| crate::hwmon::HwmonDevice::find(|d| d.is_asusec()).ok().flatten())
        .ok_or_else(|| anyhow::anyhow!("no CPU temperature sensor found; skipping"))?;
    let cpu_base = cpu_dev.basename();

    // Choose Tdie > Tctl > temp1_input
    let cpu_temp_name = choose_cpu_temp_input(&cpu_dev);

    // ── Optional AMDGPU hwmon ──
    let gpu_dev = if flags.gpu_enable {
        crate::hwmon::HwmonDevice::find(|d| d.is_amdgpu())?.or_else(|| {
            // non-fatal
            eprintln!("fancontrol-setup: amdgpu not found; GPU fan control disabled");
            None
        })
    } else {
        None
    };
    let gpu_base = gpu_dev.as_ref().map(|d| d.basename());

    // ── Build DEVPATH/DEVNAME ──
    let nct_devpath = nct.device_path();
    let cpu_devpath = cpu_dev.device_path();
    let mut devpath_entries = vec![
        format!("{}={}", nct_base, nct_devpath),
        format!("{}={}", cpu_base, cpu_devpath),
    ];
    let mut devname_entries = vec![
        format!("{}={}", nct_base, nct.name),
        format!("{}={}", cpu_base, cpu_dev.name),
    ];
    if let Some(ref gpu) = gpu_dev {
        let gb = gpu_base.clone().unwrap();
        devpath_entries.push(format!("{gb}={}", gpu.device_path()));
        devname_entries.push(format!("{gb}={}", gpu.name));
    }

    // ── Tuning parameters ──
    let min_temp = flags.min_temp;
    let max_temp = flags.max_temp;
    let min_pwm = flags.min_pwm;
    let max_pwm = flags.max_pwm;
    let hysteresis = 3u32;
    let interval = 2u32;
    let start_delta = 20u8;

    let (min_start_default, min_stop_default, eff_min_pwm) = if flags.allow_stop {
        (100u8, 0u8, 0u8)
    } else {
        let ms = (min_pwm.saturating_add(start_delta)).min(max_pwm);
        (ms, min_pwm, min_pwm)
    };

    // ── Build fancontrol config lines ──
    let mut fctemps = Vec::new();
    let mut fcfans = Vec::new();
    let mut mintemp_line = Vec::new();
    let mut maxtemp_line = Vec::new();
    let mut minpwm_line = Vec::new();
    let mut maxpwm_line = Vec::new();
    let mut minstart_line = Vec::new();
    let mut minstop_line = Vec::new();
    let mut hyst_line = Vec::new();

    // Gather GPU temp name
    let gpu_temp_name = gpu_dev.as_ref().and_then(|gpu| choose_gpu_temp_input(gpu));

    let mut found_pwm = false;

    for ch in nct.pwm_channels() {
        if !nct.fan_input_exists(ch) {
            continue;
        }
        found_pwm = true;

        // Map GPU temp to selected channels
        let use_gpu = flags.gpu_pwm_channels.contains(&ch)
            && gpu_dev.is_some()
            && gpu_temp_name.is_some();

        let temp_ref = if use_gpu {
            format!("{}/{}", gpu_base.as_ref().unwrap(), gpu_temp_name.as_ref().unwrap())
        } else {
            format!("{}/{}", cpu_base, cpu_temp_name)
        };

        fctemps.push(format!("{}/pwm{}={}", nct_base, ch, temp_ref));
        fcfans.push(format!(
            "{}/pwm{}={}/fan{}_input",
            nct_base, ch, nct_base, ch
        ));
        mintemp_line.push(format!("{}/pwm{}={}", nct_base, ch, min_temp));
        maxtemp_line.push(format!("{}/pwm{}={}", nct_base, ch, max_temp));
        minpwm_line.push(format!("{}/pwm{}={}", nct_base, ch, eff_min_pwm));
        maxpwm_line.push(format!("{}/pwm{}={}", nct_base, ch, max_pwm));
        minstart_line.push(format!("{}/pwm{}={}", nct_base, ch, min_start_default));
        minstop_line.push(format!("{}/pwm{}={}", nct_base, ch, min_stop_default));
        hyst_line.push(format!("{}/pwm{}={}", nct_base, ch, hysteresis));

        // Switch to manual so fancontrol can drive it
        let _ = nct.set_manual(ch);
    }

    if !found_pwm {
        anyhow::bail!("found nct6775 but no PWM-capable fans; skipping");
    }

    // ── Optionally add AMDGPU fan (pwm1) ──
    if let Some(ref gpu) = gpu_dev {
        if gpu.fan_input_exists(1) && gpu.pwm_channels().contains(&1) {
            if let Ok(true) = try_enable_manual(gpu, 1) {
                let gpu_temp_ref = gpu_temp_name.as_deref().unwrap_or("temp2_input");
                let gpu_min_temp = 50u32;
                let gpu_max_temp = 85u32;
                let gpu_min_pwm = 70u8;
                let gpu_max_pwm = 255u8;
                let gpu_hyst = 3u32;

                fcfans.push(format!(
                    "{}/pwm1={}/fan1_input",
                    gpu_base.as_ref().unwrap(),
                    gpu_base.as_ref().unwrap()
                ));
                fctemps.push(format!(
                    "{}/pwm1={}/{}",
                    gpu_base.as_ref().unwrap(),
                    gpu_base.as_ref().unwrap(),
                    gpu_temp_ref
                ));
                mintemp_line.push(format!(
                    "{}/pwm1={}",
                    gpu_base.as_ref().unwrap(),
                    gpu_min_temp
                ));
                maxtemp_line.push(format!(
                    "{}/pwm1={}",
                    gpu_base.as_ref().unwrap(),
                    gpu_max_temp
                ));
                if flags.allow_stop {
                    minpwm_line.push(format!("{}/pwm1=0", gpu_base.as_ref().unwrap()));
                    minstart_line.push(format!("{}/pwm1=100", gpu_base.as_ref().unwrap()));
                    minstop_line.push(format!("{}/pwm1=0", gpu_base.as_ref().unwrap()));
                } else {
                    minpwm_line.push(format!(
                        "{}/pwm1={}",
                        gpu_base.as_ref().unwrap(),
                        gpu_min_pwm
                    ));
                    let gstart = (gpu_min_pwm.saturating_add(start_delta)).min(gpu_max_pwm);
                    minstart_line.push(format!("{}/pwm1={}", gpu_base.as_ref().unwrap(), gstart));
                    minstop_line.push(format!(
                        "{}/pwm1={}",
                        gpu_base.as_ref().unwrap(),
                        gpu_min_pwm
                    ));
                }
                maxpwm_line.push(format!(
                    "{}/pwm1={}",
                    gpu_base.as_ref().unwrap(),
                    gpu_max_pwm
                ));
                hyst_line.push(format!("{}/pwm1={}", gpu_base.as_ref().unwrap(), gpu_hyst));
            } else {
                eprintln!("fancontrol-setup: GPU pwm1 manual control not available; skipping GPU");
            }
        }
    }

    // ── Write config ──
    let config = format!(
        "INTERVAL={interval}\n\
         DEVPATH={de}\n\
         DEVNAME={dn}\n\
         FCTEMPS={ft}\n\
         FCFANS={ff}\n\
         MINTEMP={mt}\n\
         MAXTEMP={xt}\n\
         MINPWM={mp}\n\
         MAXPWM={xp}\n\
         MINSTART={ms}\n\
         MINSTOP={msp}\n\
         HYSTERESIS={hy}\n",
        de = devpath_entries.join(" "),
        dn = devname_entries.join(" "),
        ft = fctemps.join(" "),
        ff = fcfans.join(" "),
        mt = mintemp_line.join(" "),
        xt = maxtemp_line.join(" "),
        mp = minpwm_line.join(" "),
        xp = maxpwm_line.join(" "),
        ms = minstart_line.join(" "),
        msp = minstop_line.join(" "),
        hy = hyst_line.join(" "),
    );

    fs::write("/etc/fancontrol.auto", &config).context("writing /etc/fancontrol.auto")?;

    // Create backup if /etc/fancontrol is a regular file (not a symlink)
    let fc_path = Path::new("/etc/fancontrol");
    if fc_path.exists() && !fc_path.is_symlink() {
        let _ = fs::copy(fc_path, "/etc/fancontrol.backup");
    }

    // Symlink
    let _ = fs::remove_file(fc_path);
    std::os::unix::fs::symlink("/etc/fancontrol.auto", fc_path)
        .context("creating /etc/fancontrol symlink")?;

    eprintln!("fancontrol-setup: wrote /etc/fancontrol.auto and symlinked /etc/fancontrol");
    Ok(())
}

/// Choose the best CPU temperature input (Tdie > Tctl > temp1).
fn choose_cpu_temp_input(dev: &crate::hwmon::HwmonDevice) -> String {
    let mut tdie: Option<u8> = None;
    let mut tctl: Option<u8> = None;

    for ch in dev.temp_inputs() {
        if let Some(label) = dev.temp_label(ch) {
            let lower = label.to_lowercase();
            if lower == "tdie" {
                tdie = Some(ch);
                break; // Tdie is preferred
            }
            if lower == "tctl" {
                tctl = Some(ch);
            }
        }
    }

    if let Some(ch) = tdie {
        format!("temp{}_input", ch)
    } else if let Some(ch) = tctl {
        format!("temp{}_input", ch)
    } else {
        "temp1_input".to_string()
    }
}

/// Choose the best GPU temperature input (junction > edge > temp2 > temp1).
fn choose_gpu_temp_input(dev: &crate::hwmon::HwmonDevice) -> Option<String> {
    let mut junction: Option<u8> = None;
    let mut edge: Option<u8> = None;

    for ch in dev.temp_inputs() {
        if let Some(label) = dev.temp_label(ch) {
            let lower = label.to_lowercase();
            if lower.contains("junction") {
                junction = Some(ch);
                break;
            }
            if lower.contains("edge") {
                edge = Some(ch);
            }
        }
    }

    if let Some(ch) = junction {
        Some(format!("temp{}_input", ch))
    } else if let Some(ch) = edge {
        Some(format!("temp{}_input", ch))
    } else if dev.path.join("temp2_input").exists() {
        Some("temp2_input".to_string())
    } else if dev.path.join("temp1_input").exists() {
        Some("temp1_input".to_string())
    } else {
        None
    }
}

/// Try to set manual mode on a PWM channel, return true if successful.
fn try_enable_manual(dev: &crate::hwmon::HwmonDevice, channel: u8) -> Result<bool> {
    let en_path = dev.path.join(format!("pwm{}_enable", channel));
    if !en_path.exists() || !is_writable(&en_path) {
        return Ok(false);
    }
    let _ = dev.set_manual(channel);
    // Verify
    if let Ok(val) = dev.read_pwm_enable(channel) {
        Ok(val == 1)
    } else {
        Ok(false)
    }
}

fn is_writable(p: &Path) -> bool {
    // Best-effort check: try opening for write
    p.metadata()
        .map(|m| !m.permissions().readonly())
        .unwrap_or(false)
}

fn require_root() -> Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        anyhow::bail!("must be root to run fan setup (try: sudo hwctl fan setup)");
    }
    Ok(())
}
