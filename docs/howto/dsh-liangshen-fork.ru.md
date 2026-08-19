# neg — форк пресета LiangShen (anchored-standard)

Собственный форк пресета **LiangShen mode** (двухфазный anchored-standard агент) для DeepSeek
Harness, поддерживаемый декларативно в этом репозитории вместо стороннего плагина
`@linxin666/dsh-liangshen` (чей patch-ряд был отмонтирован — префлайт перестал резолвить пакет).
Идентификатор пресета — **`neg`** (переименован из `liangshen-fork` по запросу пользователя): пикер,
сессии и дефолт ссылаются на `neg`.

## Что делает пресет

1. **Фаза 1** — первый запрос модели видит только поверхность Minimal: персистентный `bash` +
   `str_replace_editor`, одна строка персоны, без runtime-контекстов, инструкций воркспейса и
   каталога скиллов. Цель — «заякорить» траекторию исполнения модели (в комьюнити-эвале Minimal
   набирает выше Standard/PTC, см. [xiaobright/modeltest](https://github.com/xiaobright/modeltest)).
1. **Промоушен** — после первого сохранённого `tool/call` ждёт «минимально-подобный» первый блок
   рассуждения (содержит `we`, без `let me`), с фолбэком через 4 шага; ответ без вызовов промоутит
   сразу.
1. **Фаза 2** — провод переключается на Code Mode (PTC): один `run_code` поверх полного реестра
   инструментов, все промпт-секции возвращаются, персоне добавляется строка рабочей директории,
   инструкции воркспейса и каталог скиллов приходят с задержкой в один шаг.

## Как устроено

- Файлы пресета: `modules/user/nix-maid/apps/dsh-liangshen-fork/` (`preset.yml` — имя/описание/
  порядок в пикере, `agent.cordis.yml` — композиция, `tool-bootstrap.mjs` — двухфазный бутстрап,
  `NOTICE` — происхождение и лицензии). Поведение идентично апстриму; правится здесь.
- Модуль `modules/user/nix-maid/apps/dsh-liangshen-fork.nix` синкает файлы в
  `~/.dsh/.agent-presets/neg/` (корень discovery ростера; id пресета — `neg`) на каждом rebuild и
  логине. Синк всегда принудительный — локальные правки в `~/.dsh/.agent-presets/` затираются;
  источник истины — репозиторий. Директория исключена из авто-импорта модулей в `apps/default.nix`.
- Пресет по умолчанию: `agent-presets.default: neg` в `~/.dsh/settings.yaml` (читается hot-reload,
  применяется к **новым** сессиям; рестарт dsh не нужен). Дублирующий фолбэк в конфиге ростера
  (`- id: agent-presets / config.default` в `~/.dsh/profiles/web/cordis.patch.yml`, см.
  `dsh-market.nix`) страхует на случай сброса settings.yaml.
- Встроенный пресет `standard` удалён из сборки пакета dsh (`packages/dsh/default.nix` — postInstall
  вырезает `config/agent-presets/standard`), поэтому в пикере его нет.
- Оригинальный апстримный пресет `liangshen` (от отмонтированного плагина
  `@linxin666/dsh-liangshen`) удаляется декларативно ensure-скриптом форка; левак плагина из
  `~/.dsh/profiles/node_modules` вычищен.

## Изменение поведения

Править `modules/user/nix-maid/apps/dsh-liangshen-fork/agent.cordis.yml`, затем
`sudo nixos-rebuild switch --flake .#odin --option substitute false` (или подождать логина) —
активационный скрипт пересинкает пресет. Дефолт в пикере меняется через GUI (ростер → «Set as
default») либо правкой `settings.yaml`.

## Удаление

Убрать модуль и директорию, вернуть исключение в `apps/default.nix`, удалить
`~/.dsh/.agent-presets/neg/` и ключ `agent-presets.default` из `settings.yaml`.
