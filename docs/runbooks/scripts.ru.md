# Каталог скриптов

## Железо (`scripts/hw/`)

- [../../scripts/hw/cpu-boost.sh](../../scripts/hw/cpu-boost.sh) — включает/отключает CPU boost и печатает текущее состояние.
- [../../scripts/hw/cpu-recommend-masks.sh](../../scripts/hw/cpu-recommend-masks.sh) — предлагает ядра/маски ядра для V-Cache CPU.
- [../../scripts/hw/fancontrol-setup.sh](../../scripts/hw/fancontrol-setup.sh) — генерирует `/etc/fancontrol` из обнаруженных датчиков.
- [../../scripts/hw/fancontrol-reapply.sh](../../scripts/hw/fancontrol-reapply.sh) — переустанавливает кривые вентиляторов после сна/гибернации.
- [../../scripts/hw/fan-stop-capability-test.sh](../../scripts/hw/fan-stop-capability-test.sh) — проверяет, умеют ли вентиляторы останавливаться безопасно.

## Операции (`scripts/ops/`)

- [../../scripts/ops/collect-nextcloud-cli-debug.sh](../../scripts/ops/collect-nextcloud-cli-debug.sh) — собирает логи и диагностику nextcloudcmd.
- [../../scripts/ops/collect-quickshell-metrics.sh](../../scripts/ops/collect-quickshell-metrics.sh) — делает снэпшот метрик Quickshell для отладки.

## Разработка (`scripts/dev/`)

- [../../scripts/dev/check-markdown-language.sh](../../scripts/dev/check-markdown-language.sh) — локально проверяет языковые аннотации в Markdown.
- [../../scripts/dev/gen-options.sh](../../scripts/dev/gen-options.sh) — собирает артефакты с документацией опций/модулей.
