self: {
  rust-crane = {
    path = self + "/templates/rust-crane";
    description = "Rust project scaffold: crane, unified rust-toolchain, checks, devShell";
  };
  shell-app = {
    path = self + "/templates/shell-app";
    description = "Shell CLI packaged via writeShellApplication + devShell";
  };
  python-cli = {
    path = self + "/templates/python-cli";
    description = "Python CLI with ruff/black/pytest devShell";
  };
}
