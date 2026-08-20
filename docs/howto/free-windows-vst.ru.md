# Бесплатные Windows-VST для бриджа на Linux (yabridge / Carla wine bridge)

> Собрано субагентом 2026-08-20 (официальные источники, GitHub API). yabridge (nixpkgs) — только 64-бит;
> 32-бит-плагины исключены. Плагины с нативными Linux-сборками отмечены — их мостить НЕ нужно.

## Топ-кандидаты (Windows-only, 64-бит, headless-дружелюбные)

| Плагин | Тип | Формат | Скачать (официально) | Размер | Заметки |
| --- | --- | --- | --- | --- | --- |
| Sforzando (Plogue) | семплер/SFZ-плеер | VST2/VST3 | plogue.com/products/sforzando.html | ~3 МБ | бесплатный SFZ-плеер; GUI нужен 1 раз для загрузки банков |
| Tx16Wx | семплер | VST2/VST3 | tx16wx.com | ~30 МБ | проф. семплер, слайсинг |
| ReaPlugs (Cockos) | набор FX (ReaEQ, ReaComp…) | VST2 32/64 | reaper.fm/reaplugs | ~5 МБ | официально тестированы под WINE — самый надёжный кандидат |
| Valhalla Supermassive | реверб/дилей | VST2.4/VST3 | valhalladsp.com | ~20 МБ | лучший бесплатный реверб, v5.x |
| TDR Nova | динамический EQ | VST2/VST3 | tokyodawn.net/tdr-nova | ~10 МБ | OpenGL-UI (обычно ок под wine) |
| TDR Kotelnikov | компрессор | VST2/VST3 | tokyodawn.net/tdr-kotelnikov | ~10 МБ | мастеринг-компрессор |
| Xfer OTT | мультибанд-компрессор | VST2/VST3 | xferrecords.com/free-downloads/ott | ~2 МБ | культовый «OTT»-звук; сайт под Cloudflare — качать браузером |
| Klanghelm IVGI | сатурация | VST2/VST3 | klanghelm.com/contents/products/IVGI.html | ~2 МБ | tiny, headless OK |
| Voxengo SPAN | анализатор | VST2/VST3 | voxengo.com/product/span | ~3 МБ | для мониторинга в Carla |
| iZotope Vinyl | lo-fi/винил | VST2/VST3 | izotope.com/en/products/vinyl.html | ~30 МБ | для генеративной музыки |
| Kairatune | VA-синт | VST2 64 | futucraft.com/kairatune | ~3 МБ | zip-установка = headless-friendly |
| K1v (KORG) | M1-эмуляция | VST2 64 | korg.com/us/products/software/k1v | ~10 МБ | KORG ID, бесплатно; страница может отдавать 404 из РФ |
| Kilohearts Essentials | 30+ FX | VST2/VST3 | kilohearts.com/products/kilohearts_essentials | ~400 МБ | installer-based |

## Не мостить (есть нативные Linux-сборки)

Vital, Surge XT, Dexed, OB-Xd, Odin 2, TAL-NoiseMaker, TAL-U-NO-LX, Tyrell N6, Graillon 3 (free), Rough Rider 3 —
все имеют Linux-версии, ставятся пакетами (Vital/Surge/Dexed/OB-Xd уже есть в nixpkgs).

## MS-20-клоны

Бесплатного MS-20-клона с официальным источником не нашлось. Ближайшие проверенные эмуляции:
K1v (M1), TAL-U-NO-LX (Juno-106), OB-Xd (Oberheim), Dexed (DX7).

## Ссылки

Все ссылки — в таблице выше (проверены субагентом 2026-08-20).
Пологские (Plogue) и Xfer страницы блокируют ботов (403/Cloudflare) — скачивать в браузере.

