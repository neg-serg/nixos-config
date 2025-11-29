# AGENTS usage for secrets/home/

Scope
- Applies to user-level secrets in `secrets/home/`.
- Inherits root and `secrets/` AGENTS; this file narrows to HM wiring.

Guidelines
- Declare new secrets in `secrets/home/default.nix` with the right format/path; gate optional secrets with `lib.optionalAttrs` checks as done for cachix/vdirsyncer/nextcloud.
- Keep secret files encrypted in place with SOPS (env/yaml/binary); avoid adding temporary decrypted copies to git.
- Reuse existing paths under `/run/user/1000/secrets` or XDG config/state where possible; avoid hardcoding other locations.
- Note in the relevant module/profile when a new secret becomes required and provide a short template or `.example` alongside if helpful.
