# dsh-osm — OpenStreetMap в dsh

Плагин `dsh-osm` добавляет в DeepSeek Harness (web-профиль) четыре инструмента поверх бесплатных
публичных OSM-API, скилл с правилами этикета и интерактивную карту Leaflet прямо в чате.

## Возможности

| Инструмент     | Что делает                                                     | Сервис                          |
| -------------- | -------------------------------------------------------------- | ------------------------------- |
| `osm_geocode`  | название места/адрес → координаты                              | Nominatim (+ Photon как фолбэк) |
| `osm_reverse`  | координаты → адрес                                             | Nominatim (+ Photon как фолбэк) |
| `osm_overpass` | POI/данные по Overpass QL (`node["amenity"="cafe"](around:…)`) | overpass-api.de                 |
| `osm_route`    | маршрут между точками (driving/walking/cycling)                | OSRM (router.project-osrm.org)  |

Каждый инструмент возвращает текстовую сводку для модели и дескриптор карты (`presentationMeta`),
который web-GUI рендерит как интерактивную карточку: маркеры для геокодинга/POI, полилиния для
маршрута. В TUI/headless работает только текстовая сводка. Карта реплеится из сохранённого
дескриптора — без повторных запросов к API.

## Как устроено

- Код плагина: `modules/user/nix-maid/apps/dsh-osm/` (`package.json`, `lib/index.js` — серверная
  половина, `lib/tools.js` — инструменты, `lib/client.js` — карточка Leaflet, `assets/osm-skill.md`
  — скилл, `assets/leaflet/` — вендоренный Leaflet 1.9.4 без CDN).
- Установка: модуль `modules/user/nix-maid/apps/dsh-osm.nix` копирует плагин в
  `~/.dsh/profiles/web/node_modules/dsh-osm/` (как plain-dir, без pnpm — симлинк `@deepseek-ai` не
  переживает pnpm-записей) и дописывает строку `- insert: [{ id: osm, name: dsh-osm }]` в
  `~/.dsh/profiles/web/cordis.patch.yml`.
- Серверная часть отдаёт Leaflet по `/osm/leaflet/*` (префиксный роут webServer; префикс без
  завершающего слэша — матчер добавляет `/` сам).
- dsh работает под systemd (`dsh.service`), поэтому после изменений нужен
  `systemctl --user restart dsh.service`.

## Важно

- Файлы плагина копируются в профиль **только если их там нет** (паттерн репозитория — локальные
  правки переживают пересборку). Чтобы применить изменённую версию из модуля: удалить
  `~/.dsh/profiles/web/node_modules/dsh-osm` и перезапустить dsh.
- Публичные OSM-API бесплатные, но строго лимитированные: плагин держит ~1 запрос/сек к
  Nominatim/Overpass (очередь), шлёт корректный User-Agent и объясняет ошибки 429/403/504.
- Если Nominatim недоступен (региональная сеть), геокодинг автоматически уходит на Photon
  (`photonBase`); отключить фолбэк — `photonBase: ""`.
- Тяжёлую/продовую нагрузку лучше переводить на self-hosted экземпляры — базовые URL настраиваются в
  `Config` плагина (`nominatimBase`, `overpassBase`, `osrmBase`).
