//! The `--help` texts, byte-for-byte from the shell scripts.
//!
//! The `*.sh` names stay in the usage text on purpose: `--help` is one of the
//! outputs the port preserves, and the parity harness compares it with the
//! original scripts. The binaries are `pleamar-measure`,
//! `pleamar-describe-snap` and `pleamar-smoke`.

pub const MEASURE: &str = r#"measure.sh - run one scene for N seconds and collect a budget table

Starts one scene without touching the live session (pleamar-wm headless when
available; --live runs it in the current session instead) and collects:
  - per-second `ps`/proc samples of the scene process (RSS, CPU, threads, PSS)
  - cgroup memory/CPU when --unit names the systemd unit running it
  - `pleamar --report` output for the same window

Usage:
  measure.sh [options] [SCENE]

  SCENE may be a scene name (shells/<name>/<name>.plm) or a path to a .plm
  file. With no SCENE and exactly one scene in the tree, that one is used.

Options:
  --scene NAME      same as the positional SCENE
  --seconds N       how long to measure (default: 20)
  --interval N      seconds between samples (default: 1)
  --unit NAME       measure an already-running systemd unit (user or system):
                    its MainPID is sampled and its cgroup read; the scene is
                    not started and is not stopped. Reaches the unit's session,
                    so it uses the ambient environment.
  --out DIR         artifact base dir (default: files/pleamar/tests/evidence;
                    output lands in DIR/<YYYY-MM-DD>-<scene>.tsv/.md/.log)
  --live            use the ambient environment and start the scene in the
                    current session when WAYLAND_DISPLAY is set (killed after)
  --keep-tmp        keep the per-run temp dir for debugging
  --soft            software Vulkan: export VK_ICD_FILENAMES=<lavapipe>
                    (default /run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json)
                    unless VK_ICD_FILENAMES is already set; not the default
  -h, --help        this text

Environment:
  PLEAMAR_BIN       pleamar binary (default: pleamar from PATH)
  PLEAMAR_WM_BIN    pleamar-wm binary (default: pleamar-wm from PATH)
  PLEAMAR_SOFT_ICD  ICD used by --soft
  VK_ICD_FILENAMES  honoured when already set; --soft never overrides it

Exit status:
  0  the table and the report were written
  1  the scene died during measurement or `pleamar --report` failed
  2  bad usage, or the required tool is not available
"#;

pub const DESCRIBE_SNAP: &str = r#"describe-snap.sh - commit and verify `pleamar --say NAME describe`

Starts one scene without touching the live session (pleamar-wm headless when
available; --live runs it in the current session instead), waits for its
socket, captures the agent tree into tests/<scene>.describe.txt and kills
what it started.

Usage:
  describe-snap.sh [options] [SCENE]

  SCENE may be a scene name (shells/<name>/<name>.plm) or a path to a .plm
  file. With no SCENE and exactly one scene in the tree, that one is used.

Options:
  --update          write/rewrite the snapshot instead of diffing it
  --scene NAME      same as the positional SCENE
  --timeout N       seconds to wait for the socket (default: 15)
  --live            use the ambient environment: starts a real surface in the
                    current session when WAYLAND_DISPLAY is set (killed after)
  --keep-tmp        keep the per-run temp dir for debugging
  --systemd         start the scene as a transient --user unit (systemd-run) with
                    the same hermetic HOME/XDG sandbox, and point it at the live
                    compositor: the way to run from an agent sandbox, which cannot
                    open /dev/dri or create Wayland buffers itself (the scene then
                    draws briefly on the real screen)
  --soft            software Vulkan: export VK_ICD_FILENAMES=<lavapipe>
                    (default /run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json)
                    unless VK_ICD_FILENAMES is already set; not the default
  -h, --help        this text

Environment:
  PLEAMAR_BIN       pleamar binary (default: pleamar from PATH)
  PLEAMAR_WM_BIN    pleamar-wm binary (default: pleamar-wm from PATH)
  PLEAMAR_SOFT_ICD  ICD used by --soft
  VK_ICD_FILENAMES  honoured when already set; --soft never overrides it

Exit status:
  0  snapshot matches, or --update wrote it
  1  drift, missing committed snapshot, or the scene never answered
  2  bad usage, or the required tool is not available
"#;

pub const SMOKE: &str = r#"smoke.sh - headless render matrix for the pleamar shell

Renders one PNG per scene without using the live session: pleamar-wm headless
when available, otherwise a nested headless wlroots compositor (sway/cage)
with grim. Part files (`part ...`, includes) are skipped. Every scene is also
compiled with `pleamar --check` first, so the matrix is useful even with no
renderer available.

Usage:
  smoke.sh [options]

Options:
  --scene NAME      render only this scene (directory name under shells/)
  --seconds N       headless session length in seconds (default: 8)
  --out DIR         artifact base dir (default: files/pleamar/tests/shots;
                    output lands in DIR/<YYYY-MM-DD>/<scene>.png + .log)
  --require-render  fail (exit 2) when no renderer is available; without it
                    the compile matrix runs and rendering is skipped
  --min-bytes N     minimum PNG size treated as non-empty (default: 1024)
  --live            keep the ambient XDG dirs instead of a /tmp sandbox
                    (rendering stays headless; no surface opens in your session)
  --keep-tmp        keep the per-run temp dir for debugging
  --soft            software Vulkan: export VK_ICD_FILENAMES=<lavapipe>
                    (default /run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json)
                    unless VK_ICD_FILENAMES is already set; not the default
  -h, --help        this text

Environment:
  PLEAMAR_BIN       pleamar binary (default: pleamar from PATH)
  PLEAMAR_WM_BIN    pleamar-wm binary (default: pleamar-wm from PATH)
  PLEAMAR_HEADLESS_INPUT   synthetic input script, passed through to pleamar-wm
  PLEAMAR_SOFT_ICD  ICD used by --soft
  VK_ICD_FILENAMES  honoured when already set; --soft never overrides it

Exit status:
  0  every scene compiled, and rendered when a renderer was available
  1  a scene failed to compile or render
  2  bad usage, or pleamar is not available
"#;
