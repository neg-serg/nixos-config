# TODO: Настроить отправку почты Alertmanager

Этот хост подключен для отправки уведомлений Alertmanager на `serg.zorg@gmail.com` через SMTP Gmail, но учетные данные берутся из SOPS‑зашифрованного env‑файла, который ещё не создан. Пока секрета нет, письма отправляться не будут.

## Где настроено
- Связка Prometheus → Alertmanager и правила алёртов: `hosts/telfir/services.nix`
- Конфиг Alertmanager использует переменные окружения: `$ALERT_SMTP_USER`, `$ALERT_SMTP_PASS`
- Путь секрета, ожидаемый NixOS: `sops.secrets."alertmanager/env"` → файл `secrets/alertmanager.env.sops`

## Шаги для включения отправки почты
1) Создать App Password в Gmail
   - Включите двухфакторную аутентификацию (2‑Step Verification) для аккаунта Google.
   - Сгенерируйте App Password (выберите «Mail» → «Other») и сохраните 16‑значный пароль.

2) Создать plaintext dotenv с кредами
   - Содержимое файла (`secrets/alertmanager.env`, НЕ коммитить):
     ALERT_SMTP_USER=serg.zorg@gmail.com
     ALERT_SMTP_PASS=<APP_PASSWORD>

3) Зашифровать SOPS с использованием `.sops.yaml`
   - Зашифровать и заменить `.sops`‑файлом:
     sops -e secrets/alertmanager.env > secrets/alertmanager.env.sops
     rm -f secrets/alertmanager.env
   - Либо редактировать на месте:
     sops -e -i secrets/alertmanager.env.sops
     # добавьте две строки и сохраните

4) Применить конфигурацию
   - Сборка + переключение:
     sudo nixos-rebuild switch --flake .#telfir
   - Проверка сервисов:
     systemctl status alertmanager prometheus

5) Тест доставки (опционально)
   - Отправить тестовый алерт через API Alertmanager:
     curl -XPOST -H 'Content-Type: application/json' \
       http://127.0.0.1:9093/api/v2/alerts -d '[{\n         "labels": {"alertname": "TestEmail", "severity": "critical"},\n         "annotations": {"summary": "Test email", "description": "Manual test"}\n       }]'
   - Убедитесь, что письмо пришло на `serg.zorg@gmail.com`.

## Заметки
- Текущие SMTP‑настройки (в Nix):
  - smarthost: `smtp.gmail.com:587`
  - from: `serg.zorg@gmail.com`
  - TLS: требуется
- Если хотите локальный MTA — переключите `global.smtp_*` у Alertmanager на `127.0.0.1:25` и настройте Postfix/msmtp как релей.
- Файрволл открывает Prometheus (9090) и Alertmanager (9093) только на интерфейсе `br0`.

