# Fastfetch: чёрно-металлическая метель (анимированный логотип)

## Что это

Анимированный WebP-логотип для fastfetch: череп в капюшоне (из референса) с метелью — дизеринговая
текстура, косые штрихи снега, слои/шквалы, пульс яркости, опциональные шейдеры (invert / rgb-сдвиг)
и накопление снега (опционально).

Инструменты версионированы в files/fastfetch/, деплоятся модулем
modules/user/nix-maid/cli/fastfetch.nix в ~/.local/share/fastfetch/ и ~/.local/bin/fetch. Логотипы
генерируются на лету в ~/.local/share/fastfetch/logos/ (в git не идут).

## Использование

Быстрая команда fetch (рандомайзер):

```
fetch                            # случайный вариант (дизеринг x палитра x метель)
fetch ember                      # только палитра ember (или ash / ice)
fetch "#ff0000"                  # кастомный цвет — генерируется свой градиент
fetch --big                      # крупнее (логотип-бокс до максимума)
fetch --shader rgb               # хроматическое смещение (красный/голубой)
fetch --shader invert            # негатив
fetch --big --shader invert:rgb  # вместе
fetch --cover                   # обложка текущего трека как логотип
fetch -w 2                      # живой режим (обновление каждые 2 c)
```

В zsh определена функция fastfetch, которая делегирует в fetch (лежит в 01-init.zsh), поэтому
fastfetch ... работает так же.

## Генератор (make_blizzard.py)

```
python3 ~/.local/share/fastfetch/make_blizzard.py       --dither fs --palette ash --color "#39FF14"       --size 900x1130 --shader invert:rgb --accum 1       --storm 1.0 --wind 1.0 --frames 24 --seed 7       --out ~/.local/share/fastfetch/logos/blizzard-custom.webp

--dither  fs|atkinson|sierra|stucki|bayer|noise   (текстура черепа)
--palette ash|ember|ice   |   --color "#RRGGBB"  (свой градиент)
--shader  none|invert|rgb|invert:rgb
--accum   0 — выкл накопление; >0 — растущая шапка снега
--size    WxH  (по умолчанию 640x806)
```

Перегенерация пресетов: ~/.local/share/fastfetch/blizzard.sh fs (или без аргумента — все 6
дизерингов).

Lua/QuickJS в format (эксперим., 2.64.0+) включается оверлеем (modules/tools/default.nix) —
добавляет lua в fastfetch-unwrapped buildInputs + -DENABLE_LUA, чтобы работали lua:/qjs:
спецификаторы.

## Референс

По умолчанию REF = /home/neg/pic/necro/8a8c0e082df595deed2ef785f73c3476.jpg. Любую картинку можно
указать через --ref \<путь> — пайплайн (лицо-центр, кроп, дизеринг, метель) применяется к любому
изображению.

## Хранение (XDG)

- скрипты: ~/.local/share/fastfetch/
- логотипы: ~/.local/share/fastfetch/logos/
- ссылка: ~/.local/bin/fetch (находится в PATH через ~/.local/bin)
