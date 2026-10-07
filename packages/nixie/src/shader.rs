//! Turning the lamp's fragment shader into a compute shader.
//!
//! The lamp is drawn by greeter/shaders/nixie.frag, and this tool draws the same
//! lamp: it takes that file, swaps the few lines that belong to Qt (the
//! interpolated coordinate, the output variable, the uniform block's Qt members)
//! for the ones a headless Vulkan compute pass needs, and compiles the result
//! with glslangValidator. Nothing about the lamp itself is copied here, so the
//! picture this tool measures is the picture the login screen shows.

use anyhow::{anyhow, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Rewrite the Qt shader into a compute shader that writes `outImage`.
pub fn to_compute(src: &str) -> Result<String> {
    let mut s = src.replacen("#version 440", "#version 450", 1);
    s = s.replace(
        "layout(location = 0) in vec2 qt_TexCoord0;",
        "vec2 qt_TexCoord0;",
    );
    s = s.replace(
        "layout(location = 1) out vec4 fragColor;",
        "layout(local_size_x = 8, local_size_y = 8) in;\nlayout(binding = 2, rgba8) uniform image2D outImage;",
    );
    s = s.replace(
        "layout(binding = 0) uniform buf {",
        "layout(binding = 0, std140) uniform buf {",
    );
    s = s.replace("mat4 qt_Matrix;\n", "");
    s = s.replace("float qt_Opacity;\n", "");
    s = s.replace(
        "void main() {\nconst float PI = 3.14159265;",
        "void main() {\nconst float PI = 3.14159265;\nqt_TexCoord0 = (vec2(gl_GlobalInvocationID.xy) + 0.5) / pSize;",
    );
    let open = s
        .find("fragColor = vec4(")
        .ok_or_else(|| anyhow!("the shader has no fragColor to write from"))?;
    let tail = s[open..]
        .find("* qt_Opacity;")
        .ok_or_else(|| anyhow!("fragColor does not end with qt_Opacity"))?;
    let body = &s[open + "fragColor = ".len()..open + tail];
    let end = open + tail + "* qt_Opacity;".len();
    s.replace_range(
        open..end,
        &format!("imageStore(outImage, ivec2(gl_GlobalInvocationID.xy), {body});"),
    );
    if s.contains("fragColor") || s.contains("qt_Opacity") || s.contains("qt_Matrix") {
        return Err(anyhow!("something of Qt is left in the compute shader"));
    }
    Ok(s)
}

/// Compile GLSL to SPIR-V with glslangValidator (the one nix carries).
pub fn compile(glsl: &str, out: &Path) -> Result<PathBuf> {
    let dir = Path::new("/tmp/nixie-glsl");
    std::fs::create_dir_all(dir)?;
    let glsl_path = dir.join("nixie.comp");
    std::fs::write(&glsl_path, glsl)?;
    let spv = out.to_path_buf();
    let tool = std::env::var("NIXIE_GLSLANG").unwrap_or_else(|_| "glslangValidator".to_string());
    let out = Command::new(&tool)
        .arg("-V")
        .arg("--target-env")
        .arg("vulkan1.1")
        .arg("-o")
        .arg(&spv)
        .arg(&glsl_path)
        .output()
        .with_context(|| {
            format!("running {tool} (nix shell nixpkgs#glslang, or set NIXIE_GLSLANG)")
        })?;
    if !out.status.success() {
        return Err(anyhow!(
            "glslangValidator said:\n{}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(spv)
}
