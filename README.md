# 3x-ui self-steal Reality

Интерактивная настройка self-steal Reality для 3x-ui на Ubuntu/Debian с systemd.

## Установка через curl

Запустите на целевом сервере от пользователя с `sudo`. Переменные заранее задавать не нужно: скрипт интерактивно запросит домен и остальные параметры.

```bash
curl -fSL https://raw.githubusercontent.com/Fovway/3xui-selfsteal/main/setup-selfsteal-3xui.sh -o /tmp/setup-selfsteal-3xui.sh && sudo bash /tmp/setup-selfsteal-3xui.sh
```

Перед изменениями скрипт проверяет DNS, сервисы и занятость портов. Основная настройка выполняется только после подтверждения `APPLY`.

Только read-only предварительная проверка:

```bash
sudo bash /tmp/setup-selfsteal-3xui.sh --check --domain pl2.vline-secure.online
```

Подробная справка:

```bash
bash /tmp/setup-selfsteal-3xui.sh --help
```
