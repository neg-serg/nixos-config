# Pin every omp model role to one DeepSeek Flash route, regardless of omp's
# catalog/defaults and of `~/.omp/agent/config.yml`, so the agent never resolves
# to another provider or to a V4-era model. Explicit --model/--smol/--slow/--plan
# flags still take precedence (they override the roles below at launch).
#
# Why an overlay instead of only env vars: just smol/slow/plan have PI_*_MODEL.
# `default` — the model a session actually runs on, whose `title` inherits from
# it — has none, so it is pinned through a config overlay. Without that pin omp
# resolved to deepseek-v4-pro on this host: the three PI_* vars cover smol/slow/
# plan and the roles derived from them (`title`->plan, `advisor`->slow,
# `tiny`->smol, per the role table in the installed bundle), but not the model
# the session runs on.
#
# `deepseek-flash` is the V4.1 id and is in the installed registry; the V4-era
# `deepseek-v4-flash` these variables used before is retired.
export PI_SMOL_MODEL="${PI_SMOL_MODEL:-deepseek/deepseek-flash}" # implementation after prewalk (and `tiny`)
export PI_PLAN_MODEL="${PI_PLAN_MODEL:-deepseek/deepseek-flash}" # architectural planning (and `title`)
export PI_SLOW_MODEL="${PI_SLOW_MODEL:-deepseek/deepseek-flash}" # thorough reasoning (and `advisor`)

# --config is a `launch` flag: the subcommands (config, models, login, doctor,
# update) reject it, so a launch is handled separately. Everything else execs
# straight through with the PI_*_MODEL variables above.
_omp_cmd="$(printf '%s\n' "$1" | sed -n '/^[a-z][a-z-]*$/p')"
case "$_omp_cmd" in
  "" | launch) ;;
  *) exec @ompExe@ "$@" ;;
esac

# Default: enable prewalk (plan with slow, implement with smol), unless the
# caller opted out.
case " $* " in
  *" --no-prewalk "* | *" --no-prewalk") ;;
  *) set -- --prewalk "$@" ;;
esac

# The overlay names every role so a model change cannot leave `default` behind on
# a different route. It is removed after omp exits: `exec` would replace this
# shell and drop an EXIT trap, so the child is waited on instead.
_OMP_FLASH_MODEL="deepseek/deepseek-flash"
_OMP_ROLE_OVERLAY="$(mktemp -t omp-model-roles.XXXXXX.yml)"
trap 'rm -f "$_OMP_ROLE_OVERLAY"' EXIT INT TERM
cat > "$_OMP_ROLE_OVERLAY" << EOF
modelRoles:
  default: $_OMP_FLASH_MODEL
  smol: $_OMP_FLASH_MODEL
  slow: $_OMP_FLASH_MODEL
  plan: $_OMP_FLASH_MODEL
EOF

@ompExe@ "$@" --config "$_OMP_ROLE_OVERLAY"
