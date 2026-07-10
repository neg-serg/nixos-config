mod commands;
mod daemon;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "hypr-focus")]
#[command(about = "Hyprland focus history tracker and window management CLI", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start background focus tracking daemon
    Daemon,
    /// Focus the previously focused window
    Switch,
    /// Jump to a workspace by ID or name
    Workspace {
        /// Workspace ID or name
        target: String,
    },
    /// Move the active window to a workspace, optionally follow
    MoveToWorkspace {
        /// Target workspace ID
        target: String,
        /// Also switch to the target workspace
        #[arg(long)]
        follow: bool,
    },
    /// Toggle floating for the active window
    Float,
    /// Toggle fullscreen for the active window
    Fullscreen,
    /// Toggle pin for the active window
    Pin,
    /// Set or toggle the layout (master or dwindle)
    Layout {
        /// Layout name (master, dwindle) — omit to toggle
        name: Option<String>,
    },
    /// Cycle master orientation
    Orientation,
    /// Adjust or set the master split ratio
    SplitRatio {
        /// Value: '+0.1', '-0.1', or an absolute value like '0.3'
        value: String,
    },
    /// Swap the active window with the master window
    SwapMaster,
    /// Add the active window to the master list
    AddMaster,
    /// Remove the active window from the master list
    RemoveMaster,
    /// Toggle dwindle split direction
    ToggleSplit,
    /// Preselect a split direction for the next window
    Preselect {
        /// Direction: l, r, u, d
        direction: String,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon => commands::daemon(),
        Commands::Switch => commands::switch_window(),
        Commands::Workspace { target } => commands::workspace(&target),
        Commands::MoveToWorkspace { target, follow } => commands::move_to_workspace(&target, follow),
        Commands::Float => commands::float(),
        Commands::Fullscreen => commands::fullscreen(),
        Commands::Pin => commands::pin(),
        Commands::Layout { name } => commands::layout(name.as_deref()),
        Commands::Orientation => commands::orientation(),
        Commands::SplitRatio { value } => commands::split_ratio(&value),
        Commands::SwapMaster => commands::swap_master(),
        Commands::AddMaster => commands::add_master(),
        Commands::RemoveMaster => commands::remove_master(),
        Commands::ToggleSplit => commands::toggle_split(),
        Commands::Preselect { direction } => commands::preselect(&direction),
    }
}
