mod cpu;
mod fan;
mod hwmon;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "hwctl",
    about = "Hardware control for NixOS — CPU boost, V-Cache masks, fan control"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// CPU frequency and topology control
    Cpu {
        #[command(subcommand)]
        action: CpuAction,
    },
    /// Fan control (Nuvoton nct6799 via sysfs)
    Fan {
        #[command(subcommand)]
        action: FanAction,
    },
}

#[derive(Subcommand)]
enum CpuAction {
    /// Read or change CPU boost state (status|on|off|toggle)
    Boost {
        /// "status" reads, "on"/"off" sets, "toggle" flips
        state: Option<String>,
    },
    /// Print recommended kernel CPU masks for V-Cache CCD isolation
    Masks,
}

#[derive(Subcommand)]
enum FanAction {
    /// Restart fancontrol service for automatic fan curve
    Auto,
    /// Set all CPU/case fans to a fixed PWM value (default: 70)
    Manual {
        /// PWM value 0-255 (default: 70)
        pwm: Option<u8>,
    },
    /// Auto-generate /etc/fancontrol.auto and symlink /etc/fancontrol
    Setup {
        /// Minimum temperature for fan curve (°C, default: 35)
        #[arg(long, default_value_t = 35)]
        min_temp: u32,

        /// Maximum temperature for fan curve (°C, default: 75)
        #[arg(long, default_value_t = 75)]
        max_temp: u32,

        /// Minimum PWM duty cycle (0-255, default: 70)
        #[arg(long, default_value_t = 70)]
        min_pwm: u8,

        /// Maximum PWM duty cycle (0-255, default: 255)
        #[arg(long, default_value_t = 255)]
        max_pwm: u8,

        /// Allow fans to stop completely
        #[arg(long, default_value_t = false)]
        allow_stop: bool,

        /// Enable AMDGPU fan control
        #[arg(long, default_value_t = false)]
        gpu_enable: bool,

                /// PWM channels that follow GPU temperature (e.g. --gpu-pwm-channels 2 --gpu-pwm-channels 3)
                #[arg(long)]
                gpu_pwm_channels: Vec<u8>,
    },
    /// Post-resume hook: re-enable manual PWM and restart fancontrol
    Reapply {
        /// Also handle AMDGPU pwm1
        #[arg(long, default_value_t = false)]
        gpu: bool,
    },
    /// Test which PWM channels support full stop (PWM=0 → 0 RPM)
    TestStop {
        /// Include CPU/PUMP/AIO-labeled channels (unsafe)
        #[arg(long, default_value_t = false)]
        include_cpu: bool,

        /// Specific hwmon path or name to test
        #[arg(long)]
        device: Option<String>,

        /// Seconds to wait after setting PWM=0 (default: 6)
        #[arg(long, default_value_t = 6)]
        wait: u64,

        /// RPM threshold considered "stopped" (default: 50)
        #[arg(long, default_value_t = 50)]
        threshold: u32,

        /// Only list detected channels, no testing
        #[arg(long, default_value_t = false)]
        list: bool,
    },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Cpu { action } => match action {
            CpuAction::Boost { state } => {
                let action = state.as_deref().unwrap_or("status");
                cpu::run_boost(action)?;
            }
            CpuAction::Masks => {
                cpu::run_masks()?;
            }
        },
        Commands::Fan { action } => match action {
            FanAction::Auto => {
                fan::auto::run_auto()?;
            }
            FanAction::Manual { pwm } => {
                fan::manual::run_manual(pwm)?;
            }
            FanAction::Setup {
                min_temp,
                max_temp,
                min_pwm,
                max_pwm,
                allow_stop,
                gpu_enable,
                gpu_pwm_channels,
            } => {
                let flags = fan::setup::SetupFlags {
                    min_temp,
                    max_temp,
                    min_pwm,
                    max_pwm,
                    allow_stop,
                    gpu_enable,
                    gpu_pwm_channels,
                };
                fan::setup::run_setup(flags)?;
            }
            FanAction::Reapply { gpu } => {
                fan::reapply::run_reapply(gpu)?;
            }
            FanAction::TestStop {
                include_cpu,
                device,
                wait,
                threshold,
                list,
            } => {
                let flags = fan::test_stop::TestFlags {
                    include_cpu,
                    device,
                    wait_secs: wait,
                    threshold,
                    list_only: list,
                };
                fan::test_stop::run_test_stop(flags)?;
            }
        },
    }

    Ok(())
}
