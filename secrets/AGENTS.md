# AGENTS usage for secrets/

Scope
- Applies to the `secrets/` tree (including nested `home/`).
- Root AGENTS rules still apply; nested files can further scope.

Guidelines
- Keep everything encrypted via SOPS using the repo `.sops.yaml`; never commit plaintext secrets (use `.example` or comments for templates).
- Edit secrets with `sops -i <file>` to avoid leaving decrypted copies; remove any `.dec` or backup files before commit.
- Prefer deterministic names and formats (`yaml`, `dotenv`, `binary`) and keep paths stable for downstream modules that read them.
- Document new secrets in the corresponding module/profile and provide minimal usage notes if format is non-obvious.
