# Force DeepSeek models for all model roles regardless of OMP defaults/config.yml,
# so the agent never falls back to a provider without an API key (e.g. cerebras,
# zai-glm-4.7). Explicit --model/--smol/--slow/--plan flags still take precedence.
# The omp registry (17.3.4) knows the V4-era DeepSeek ids only: `deepseek-flash`
# is absent from its bundled catalog, so naming it here would fail model
# resolution. The retired `deepseek-v4-flash` route is what the API serves
# from V4.1-Flash at Flash pricing, and V4 Pro is retired on 2026-09-14, so
# every role below names that one route.
export PI_SMOL_MODEL="${PI_SMOL_MODEL:-deepseek/deepseek-v4-flash}" # implementation after prewalk
export PI_PLAN_MODEL="${PI_PLAN_MODEL:-deepseek/deepseek-v4-flash}" # architectural planning
export PI_SLOW_MODEL="${PI_SLOW_MODEL:-deepseek/deepseek-v4-flash}" # thorough reasoning

# Default: enable prewalk (plan with slow, implement with smol) — but only for `launch`,
# never for subcommands (config, update, doctor, login, etc.).
_omp_cmd="$(printf '%s\n' "$1" | sed -n '/^[a-z][a-z-]*$/p')"
case " $* " in
  *" --no-prewalk "* | *" --no-prewalk") ;;
  *) case "$_omp_cmd" in
    "" | launch) set -- --prewalk "$@" ;;
  esac ;;
esac
exec @ompExe@ "$@"
