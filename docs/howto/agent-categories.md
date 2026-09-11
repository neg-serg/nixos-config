# Intent categories instead of model names

Port from **oh-my-opencode (oh-my-openagent)**. Idea: delegate by intent, not by model name. A model
name creates distributional bias — the model behaves differently when it thinks of itself as "gpt-X"
or "claude-Y"; a category instead describes WHAT needs to be done, and the harness picks the model.

## Categories (from oh-my-openagent)

| Category             | Purpose                                |
| -------------------- | -------------------------------------- |
| `ultrabrain`         | Complex logic, architectural decisions |
| `deep`               | Autonomous research + execution        |
| `quick`              | Single-file edits, typos               |
| `visual-engineering` | Frontend, UI/UX, design                |
| `writing`            | Texts                                  |

## How this already lives here

The omp wrapper (`modules/dev/omp.nix`) does the same thing through roles:

- `PI_SMOL_MODEL` — implementation after prewalk (analog of `quick`/`deep`);
- `PI_PLAN_MODEL` / `PI_SLOW_MODEL` — planning and deep reasoning (analog of `ultrabrain`).

## Rule

- In prompts and delegation, name the role/intent, not a concrete model.
- The harness picks the model for the role (here — the omp wrapper with DeepSeek models by default).
- When adding a new role: first determine which intent it covers, then the models.
