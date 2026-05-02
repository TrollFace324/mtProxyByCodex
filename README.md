# mtProxyByCodex

Простая установка Telegram MTProto proxy на VPS через [9seconds/mtg](https://github.com/9seconds/mtg).

Скрипт сам скачивает актуальный релиз `mtg`, проверяет SHA256 checksum, создает `/etc/mtg.toml`, настраивает `systemd`, открывает порт в `ufw`/`firewalld` если они активны, запускает сервис и печатает готовую ссылку для Telegram.

## Быстрая установка

После публикации репозитория на GitHub замени `YOUR_GITHUB_USERNAME` на свой логин:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/mtProxyByCodex/main/install.sh | sudo bash
```

По умолчанию прокси поднимается на `443/tcp` с FakeTLS-доменом `www.microsoft.com`.

## Установка с параметрами

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/mtProxyByCodex/main/install.sh | sudo bash -s -- --port 8443 --host www.cloudflare.com
```

Если репозиторий уже склонирован на сервер:

```bash
sudo bash install.sh --port 443 --host www.microsoft.com
```

Доступные параметры:

```text
--port PORT          Порт, по умолчанию 443
--bind ADDR:PORT     Полный адрес bind, по умолчанию 0.0.0.0:<port>
--host HOSTNAME      Домен для FakeTLS-секрета, по умолчанию www.microsoft.com
--secret SECRET      Использовать готовый mtg secret вместо генерации нового
--version VERSION    Поставить конкретную версию mtg, например v2.2.8
--no-firewall        Не менять правила ufw/firewalld
--force              Пропустить проверку занятого порта
```

Те же настройки можно передать через переменные окружения:

```bash
MTG_PORT=443 MTG_FAKE_TLS_HOST=www.microsoft.com sudo -E bash install.sh
```

## Управление

Проверить статус:

```bash
systemctl status mtg
```

Посмотреть логи:

```bash
journalctl -u mtg -f
```

Показать ссылку для Telegram еще раз:

```bash
/usr/local/bin/mtg access /etc/mtg.toml
```

Перезапустить:

```bash
systemctl restart mtg
```

## Обновление

Запусти установку повторно. Скрипт сделает backup старых `/etc/mtg.toml` и `/etc/systemd/system/mtg.service`, скачает выбранную или последнюю версию `mtg` и перезапустит сервис.

```bash
sudo bash install.sh
```

## Удаление

Удалить сервис и бинарник, но оставить конфиг:

```bash
sudo bash uninstall.sh
```

Удалить вместе с `/etc/mtg.toml`:

```bash
sudo bash uninstall.sh --purge
```

## Требования

Поддерживаются Linux-серверы с `systemd`: Ubuntu, Debian, AlmaLinux/Rocky/CentOS/Fedora и похожие дистрибутивы. Нужен root-доступ или запуск через `sudo`.

Если у провайдера есть отдельный cloud firewall, открой там выбранный TCP-порт вручную.

## Безопасность

Не коммить пароли, SSH-ключи, реальные `.env` файлы и приватные конфиги. Если пароль от VPS уже был отправлен в чат или кому-то еще, лучше сменить его после настройки.
