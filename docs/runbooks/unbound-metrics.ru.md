# Метрики Unbound DNS: Prometheus + Grafana

Цель: наблюдать качество локального резолвера Unbound — время ответа, долю DNSSEC‑валидации,
кэш‑хиты/миссы и смежные показатели. Работает с DNS‑стеком из этого репо: приложения →
systemd‑resolved (127.0.0.53) → AdGuardHome (127.0.0.1:53) → Unbound (127.0.0.1:5353).

## Что делает эта интеграция

- Включает расширенную статистику Unbound и `unbound-control` на localhost (127.0.0.1:8953) для
  чтения метрик.
- Запускает Prometheus Unbound exporter (по умолчанию 127.0.0.1:9167), который конвертирует
  статистику в метрики Prometheus.
- Добавляет scrape‑job `unbound` в Prometheus и источник Prometheus в Grafana, чтобы метрики были
  готовы к запросам.

Все контрольные/скрейп эндпоинты по умолчанию доступны только на localhost. Открывать фаервол не
требуется.

## Включение (фрагменты NixOS)

Если вы используете роль `roles.homelab`, Unbound уже включён и настроен как апстрим для
AdGuardHome. Чтобы собирать метрики, включите экспортер, скрейп‑задачу и добавьте источник
Prometheus в Grafana:

```nix
{ lib, config, ... }: {
  # Экспортер Unbound (только localhost)
  services.prometheus.exporters.unbound = {
    enable = true;
    port = 9167;
    openFirewall = false; # оставляем только локальный доступ
  };

  # Prometheus с job для unbound
  services.prometheus = {
    enable = true;
    scrapeConfigs = [
      {
        job_name = "unbound";
        static_configs = [ {
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.unbound.port}" ];
        } ];
      }
    ];
  };

  # Grafana: источник Prometheus (Loki провиженится отдельно)
  services.grafana.provision.datasources.settings.datasources = [
    {
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://127.0.0.1:${toString config.services.prometheus.port}";
      isDefault = false;
    }
  ];
}
```

Детали модуля в этом репо:

- Профиль Unbound включает `extended-statistics: yes` и `remote-control` на `127.0.0.1:8953` без
  TLS‑сертификатов. Этого достаточно для экспортера. Если нужен TLS на сокете управления —
  сгенерируйте cert/key для Unbound и передайте соответствующие параметры экспортеру; при этом
  оставляйте оба на loopback.

## Проверка

- Экспортер: `curl -s http://127.0.0.1:9167/metrics | head`
- Unbound control: `unbound-control -c /etc/unbound/unbound.conf stats_noreset | head`
- Цели Prometheus: откройте `http://<host>:9090/targets` и найдите job `unbound`.

## Grafana: панели и примеры запросов

Названия метрик зависят от версии экспортера и Unbound. Используйте автодополнение Grafana по
префиксу `unbound_` и адаптируйте примеры ниже.

- Время ответа (p50/p95). Если доступны гистограммы `unbound_histogram_request_time_seconds_bucket`:

  - p50:
    `histogram_quantile(0.5, sum by (le) (rate(unbound_histogram_request_time_seconds_bucket[5m])))`
  - p95:
    `histogram_quantile(0.95, sum by (le) (rate(unbound_histogram_request_time_seconds_bucket[5m])))`

  Если гистограмм нет, используйте уже настроенный Blackbox DNS‑пробер:

  - `probe_duration_seconds{job="blackbox-dns"}`

- Доля валидных DNSSEC ответов:

  - `sum(rate(unbound_num_answer_secure_total[5m])) / (sum(rate(unbound_num_answer_secure_total[5m])) + sum(rate(unbound_num_answer_bogus_total[5m])))`

- Эффективность кэша:

  - Хиты: `sum(rate(unbound_num_cachehits_total[5m]))`
  - Миссы: `sum(rate(unbound_num_cachemiss_total[5m]))`
  - Hit ratio:
    `sum(rate(unbound_num_cachehits_total[5m])) / (sum(rate(unbound_num_cachehits_total[5m])) + sum(rate(unbound_num_cachemiss_total[5m])))`

- Трафик и качество (опционально):

  - QPS: `sum(rate(unbound_num_queries_total[5m]))`
  - По RCODE: `sum by (rcode) (rate(unbound_num_answer_rcode_total[5m]))`
  - По QTYPE: `sum by (type) (rate(unbound_num_query_type_total[5m]))`

## Заметки по безопасности

- `remote-control` в этом репо привязан к `127.0.0.1` и без TLS (`control-use-cert: no`). Это
  безопасно для односерверного сценария, где экспортер локальный. Не публикуйте 8953/TCP наружу.
- Для межхостового скрейпа или повышенных требований включите TLS у Unbound control и запустите
  экспортер с нужными параметрами, оставив оба на loopback.

## Траблшутинг

- Экспортер работает, но метрик нет: проверьте, что `unbound-control status` выполняется от имени
  пользователя сервиса экспортера; убедитесь в включении `remote-control` и листенере на
  `127.0.0.1:8953`.
- Нет гистограмм задержек: экспортер/Unbound может их не предоставлять — используйте
  `probe_duration_seconds` из Blackbox DNS до появления гистограмм.
- Нулевая доля secure: проверьте `servicesProfiles.unbound.dnssec.enable = true;` и поддержку DNSSEC
  у апстримов при форвардинге.
