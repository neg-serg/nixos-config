use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;

/// Represents a discovered hwmon device in /sys/class/hwmon/
#[derive(Clone, Debug)]
pub struct HwmonDevice {
    pub path: PathBuf,
    pub name: String,
}

impl HwmonDevice {
    /// Scan /sys/class/hwmon/ and return all detected devices.
    pub fn discover() -> Result<Vec<HwmonDevice>> {
        let mut devices = Vec::new();
        let dir = PathBuf::from("/sys/class/hwmon");
        if !dir.exists() {
            return Ok(devices);
        }
        for entry in fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            let name_file = path.join("name");
            if !name_file.exists() {
                continue;
            }
            let name = fs::read_to_string(&name_file)?.trim().to_string();
            devices.push(HwmonDevice { path, name });
        }
        Ok(devices)
    }

    // ── classifier helpers ──

    pub fn is_nuvoton(&self) -> bool {
        self.name.starts_with("nct")
    }

    pub fn is_amdgpu(&self) -> bool {
        self.name.contains("amdgpu")
    }

    pub fn is_k10temp(&self) -> bool {
        self.name.contains("k10temp")
    }

    pub fn is_asusec(&self) -> bool {
        self.name.contains("asusec")
    }

    /// Find the first Nuvoton (nct*) hwmon device, with fallback via readlink.
    pub fn find_nuvoton() -> Result<Option<HwmonDevice>> {
        let all = Self::discover()?;
        for d in &all {
            if d.is_nuvoton() {
                return Ok(Some(d.clone()));
            }
        }
        // Fallback: check readlink target for "nct"
        for d in &all {
            if let Ok(target) = fs::read_link(&d.path) {
                if target.to_string_lossy().contains("nct") {
                    return Ok(Some(d.clone()));
                }
            }
        }
        Ok(None)
    }

    /// Find the first hwmon matching a predicate.
    pub fn find<F>(pred: F) -> Result<Option<HwmonDevice>>
    where
        F: Fn(&HwmonDevice) -> bool,
    {
        for d in Self::discover()? {
            if pred(&d) {
                return Ok(Some(d));
            }
        }
        Ok(None)
    }

    // ── PWM I/O ──

    pub fn read_pwm(&self, channel: u8) -> Result<u8> {
        let val = fs::read_to_string(self.path.join(format!("pwm{}", channel)))
            .context(format!("reading pwm{}", channel))?;
        Ok(val.trim().parse::<u8>()?)
    }

    pub fn write_pwm(&self, channel: u8, value: u8) -> Result<()> {
        fs::write(self.path.join(format!("pwm{}", channel)), format!("{value}\n"))
            .context(format!("writing pwm{}", channel))
    }

    pub fn read_pwm_enable(&self, channel: u8) -> Result<u8> {
        let val = fs::read_to_string(self.path.join(format!("pwm{}_enable", channel)))
            .context(format!("reading pwm{}_enable", channel))?;
        Ok(val.trim().parse::<u8>()?)
    }

    pub fn set_pwm_mode(&self, channel: u8, mode: u8) -> Result<()> {
        fs::write(
            self.path.join(format!("pwm{}_enable", channel)),
            format!("{mode}\n"),
        )
        .context(format!("setting pwm{}_enable={}", channel, mode))
    }

    /// Set manual mode (enable=1) for the given PWM channel.
    pub fn set_manual(&self, channel: u8) -> Result<()> {
        self.set_pwm_mode(channel, 1)
    }

    /// Set automatic/thermal-cruise mode (enable=2).
    #[allow(dead_code)]
    pub fn set_auto(&self, channel: u8) -> Result<()> {
        self.set_pwm_mode(channel, 2)
    }

    // ── Fan input ──

    pub fn read_fan_rpm(&self, channel: u8) -> Result<u32> {
        let val = fs::read_to_string(self.path.join(format!("fan{}_input", channel)))
            .context(format!("reading fan{}_input", channel))?;
        Ok(val.trim().parse::<u32>()?)
    }

    pub fn fan_input_exists(&self, channel: u8) -> bool {
        self.path.join(format!("fan{}_input", channel)).exists()
    }

    pub fn fan_label(&self, channel: u8) -> Option<String> {
        let p = self.path.join(format!("fan{}_label", channel));
        if p.exists() {
            fs::read_to_string(&p).ok().map(|s| s.trim().to_string())
        } else {
            None
        }
    }

    // ── Temperature ──

    #[allow(dead_code)]
    pub fn read_temp(&self, channel: u8) -> Result<u32> {
        let val = fs::read_to_string(self.path.join(format!("temp{}_input", channel)))
            .context(format!("reading temp{}_input", channel))?;
        Ok(val.trim().parse::<u32>()?)
    }

    pub fn temp_label(&self, channel: u8) -> Option<String> {
        let p = self.path.join(format!("temp{}_label", channel));
        if p.exists() {
            fs::read_to_string(&p).ok().map(|s| s.trim().to_string())
        } else {
            None
        }
    }

    // ── Inventory ──

    /// List PWM channels on this device (pwm1 … pwm9).
    pub fn pwm_channels(&self) -> Vec<u8> {
        let mut ch = Vec::new();
        for i in 1..=9 {
            if self.path.join(format!("pwm{}", i)).exists() {
                ch.push(i);
            }
        }
        ch
    }

    /// List temperature input indices on this device.
    pub fn temp_inputs(&self) -> Vec<u8> {
        let mut ch = Vec::new();
        for i in 1..=9 {
            if self.path.join(format!("temp{}_input", i)).exists() {
                ch.push(i);
            }
        }
        ch
    }

    /// Return an identifier string used in fancontrol config (e.g. "hwmon5").
    pub fn basename(&self) -> String {
        self.path
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default()
    }

    /// Resolve the real device path relative to /sys/ (for fancontrol config).
    ///
    /// fancontrol(8) from lm_sensors validates DEVPATH at startup by running
    /// `readlink -f $hwmon/device`, which resolves symlinks to their canonical
    /// path (e.g. `devices/platform/nct6775.656`).  We must match that format
    /// exactly or fancontrol refuses to start with "Device path has changed".
    pub fn device_path(&self) -> String {
        let devlink = self.path.join("device");
        // canonicalize resolves the full chain of symlinks, matching readlink -f
        if let Ok(canonical) = devlink.canonicalize() {
            canonical
                .to_string_lossy()
                .to_string()
                .trim_start_matches("/sys/")
                .to_string()
        } else if let Ok(canonical) = self.path.canonicalize() {
            canonical
                .to_string_lossy()
                .to_string()
                .trim_start_matches("/sys/")
                .to_string()
        } else {
            self.path
                .to_string_lossy()
                .to_string()
                .trim_start_matches("/sys/")
                .to_string()
        }
    }
}
