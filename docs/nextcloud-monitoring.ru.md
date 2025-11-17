# Мониторинг Nextcloud: Blackbox + метрики PHP-FPM

Цель: наблюдать доступность и задержку Nextcloud через Blackbox, а также состояние пула PHP‑FPM
через экспортер Prometheus. Дополняет существующие логи Loki и системные метрики.

## Что уже настроено в этом репо

- Blackbox‑проба HTTPS к `https://telfir/status.php` с разрешением самоподписанных сертификатов
  (LAN). Джоб `blackbox-https-insecure` указывает на локальный Blackbox exporter.
- Опциональный экспортер PHP‑FPM настроен на чтение статуса пула Nextcloud через unix‑сокет со
  статус‑путём `/status`.
- В Prometheus добавлен джоб `phpfpm` для экспортера.

Все эндпоинты по умолчанию доступны только на localhost; наружу ничего не публикуется.

## Фрагменты NixOS, используемые здесь

Blackbox (уже в конфиге хоста):

```nix
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    openFirewall = true; # в этом репо ограничено интерфейсом br0 через firewallFilter
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "blackbox-https-insecure";
      metrics_path = "/probe";
      params.module = [ "http_2xx_insecure" ];
      static_configs = [ { targets = [ "https://telfir/status.php" ]; } ];
      relabel_configs = [
        { source_labels = [ "__address__" ]; target_label = "__param_target"; }
        { source_labels = [ "__param_target" ]; target_label = "instance"; }
        { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
      ];
    }
  ];
}
```

Экспортер PHP‑FPM (опционально, включён здесь):

```nix
{
  # Пул Nextcloud должен публиковать статус
  services.phpfpm.pools.nextcloud.settings."pm.status_path" = "/status";

  services.prometheus.exporters."php-fpm" = {
    enable = true;
    openFirewall = false; # только локально
    extraFlags = [
      "--phpfpm.scrape-uri=unix:///run/phpfpm/nextcloud.sock;/status"
    ];
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "phpfpm";
      static_configs = [ { targets = [ "127.0.0.1:${toString config.services.prometheus.exporters."php-fpm".port}" ]; } ];
    }
  ];
}
```

## Проверка

- Blackbox: в Prometheus → Targets найдите `blackbox-https-insecure` с
  `instance="https://telfir/status.php"`.
- Экспортер PHP‑FPM: `curl -s http://127.0.0.1:9253/metrics | head`.

## Grafana: полезные запросы

Используйте автодополнение по префиксам `probe_` и `php_fpm_` — названия метрик могут отличаться в
зависимости от версии экспортера.

- Задержка Nextcloud (панель/алерт):

  - `probe_duration_seconds{job="blackbox-https-insecure", instance="https://telfir/status.php"}`

- Состояние пула PHP‑FPM:

  - Активные процессы: `php_fpm_processes{state="active"}` или `php_fpm_active_processes`
  - Праздные процессы: `php_fpm_processes{state="idle"}` или `php_fpm_idle_processes`
  - Очередь слушателя: `php_fpm_listen_queue`
  - Достигнут максимум процессов: `increase(php_fpm_max_children_reached[1h])`
  - Принятые соединения: `rate(php_fpm_accepted_connections_total[5m])`

## Алерты (примеры)

- Отказ пробы (уже присутствует в репо для всех HTTP blackbox‑джобов):

  - `probe_success{job=~"blackbox-http|blackbox-https-insecure"} == 0` в течение 1m

- Высокая задержка Nextcloud (пример):

  - `probe_duration_seconds{job="blackbox-https-insecure", instance="https://telfir/status.php"} > 2`
    в течение 5m

Пороговые значения подбирайте под вашу среду.
