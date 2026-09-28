# passwall2-hpwnr-patch

Интеграция поддержки зашифрованных подписок [hpwnr](https://github.com/Omegaplexx/hpwnr)
в [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) на OpenWrt.

Позволяет PassWall2 работать с зашифрованными ссылками подписок напрямую:

- `happ://crypt5/…`
- `happ://crypt3/…`
- `v2raytun://crypt/…`
- `https://example.com/SALT-PATH/MASKED?key=keyNN`

Обычные подписки (`https://…`) продолжают работать без изменений.

---

## Как это работает

```
happ://crypt5/…  или  v2raytun://crypt/…
        │
        ▼  hpwnr (локальная расшифровка ссылки, без сети)
https://example.com/SALT-PATH/MASKED?key=key11
        │
        ├──▶ curl -I  (заголовки: Subscription-Userinfo и др.)
        │
        └──▶ hpwnr … b64  (HTTP-запрос + AES-128-GCM расшифровка тела)
                    │
                    ▼
          vless://…
          vmess://…
          hysteria2://…
                    │
                    ▼
          PassWall2 parse_link()  →  серверы добавлены
```

Патч минимально-инвазивный: в оригинальный `subscribe.lua` вносятся
**ровно 2 вставки** и **ноль удалений**. Оригинальный файл сохраняется
как `subscribe.lua.pre-hpwnr.bak`.

---

## Требования

- OpenWrt 25.x (apk) или OpenWrt 23/24.x (opkg)
- [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) установлен
- Бинарник `hpwnr` для вашей архитектуры (см. ниже)

---

## Установка

### Быстрая (интерактивная)

```bash
# wget
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh

# curl
curl -sSL https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh
```

Скрипт спросит, нужно ли скачать бинарник `hpwnr`.

### С флагами

Флаги передаются через `sh -s --`:

```bash
# wget
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- [флаги]

# curl
curl -sSL https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- [флаги]
```

#### Доступные флаги

| Флаг | Описание |
|------|----------|
| `--with-hpwnr` / `-H` | Скачать и установить бинарник `hpwnr` из этого репозитория |
| `--yes` / `-y` | Тихий режим — отвечать «да» на все вопросы |
| `uninstall` | Удалить патч и все связанные файлы |

#### Примеры

```bash
# Установить патч + скачать hpwnr (интерактивно)
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- --with-hpwnr

# Полностью тихая установка со всем включая hpwnr
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- --with-hpwnr --yes

# Только патч, без hpwnr, тихо
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- --yes

# Удаление (интерактивное, спросит про бинарник hpwnr)
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- uninstall

# Удаление тихое (hpwnr binary НЕ удаляется, default = n)
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- uninstall --yes
```

---

## Что устанавливается

| Файл | Назначение |
|------|------------|
| `/usr/share/passwall2/hpwnr.lua` | Lua-модуль интеграции (не часть пакета PassWall2) |
| `/usr/bin/passwall2-hpwnr-patch` | Идемпотентный скрипт патча/снятия патча |
| `/etc/init.d/passwall2-hpwnr` | Автоприменение патча при каждой загрузке (START=99) |
| `/etc/apk/commit_hooks.d/passwall2-hpwnr` | Автоприменение после `apk` install/upgrade (OpenWrt 25.x) |
| `/etc/opkg/post-install.d/passwall2-hpwnr` | Автоприменение после `opkg` install/upgrade (OpenWrt ≤24.x) |
| `/usr/bin/hpwnr` | Бинарник hpwnr (только при `--with-hpwnr`) |

Все файлы автоматически добавляются в `/etc/sysupgrade.conf`.

---

## Выживаемость после обновлений

| Событие | Что происходит |
|---------|----------------|
| `apk upgrade luci-app-passwall2` | `subscribe.lua` перезаписывается → apk commit hook сразу переприменяет патч |
| `opkg upgrade luci-app-passwall2` | `subscribe.lua` перезаписывается → opkg post-install hook сразу переприменяет патч |
| Перезагрузка роутера | init.d (START=99) проверяет и переприменяет патч при необходимости |
| **sysupgrade** (обычный) | Все файлы из `sysupgrade.conf` восстанавливаются; пакеты переустанавливаются вручную → при первой загрузке init.d применит патч |
| **Attended SysUpgrade** (owut) | Пакеты включаются в новый образ автоматически; файлы из `sysupgrade.conf` восстанавливаются; init.d применяет патч при первой загрузке |

---

## bинарник hpwnr

> ЭТО ВСЁ ВРЕМЕННО!!! 
> После обновления в [hpwnr](https://github.com/Omegaplexx/hpwnr) здесь они будут удалены!

В этом репозитории (`files/hpwnr/`) находятся бинарники для:

| Архитектура | Устройства |
|-------------|------------|
| `x86_64` | x86 роутеры/VM |

Определить архитектуру своего роутера:
```bash
uname -m
```
Если нужной архитектуры нет — посмотрите в оригинале [hpwnr](https://github.com/Omegaplexx/hpwnr)

---

## Ручное управление патчем

```bash
# Применить патч вручную
passwall2-hpwnr-patch

# Проверить статус (пропатчено или нет)
grep -q "HPWNR_PATCHED" /usr/share/passwall2/subscribe.lua \
    && echo "PATCHED" || echo "CLEAN"

# Снять патч (восстановить оригинальный subscribe.lua)
passwall2-hpwnr-patch unapply
```

---

## Удаление

```bash
# Интерактивное (спросит, удалять ли бинарник hpwnr)
wget -qO- https://raw.githubusercontent.com/WhiteDuke-IOI/passwall2-hpwnr-patch/main/install.sh | sh -s -- uninstall
```

Что удаляется:
- Патч снимается с `subscribe.lua` (восстанавливается из бэкапа или через переустановку пакета)
- Все файлы из таблицы выше
- Блок записей из `/etc/sysupgrade.conf`
- Бинарник `/usr/bin/hpwnr` — **только по запросу**

---

## Отладка

```bash
# Проверить что в sysupgrade войдут наши файлы
sysupgrade -l | grep hpwnr

# Смотреть лог PassWall2 в реальном времени
logread -f | grep -i passwall

# Или напрямую
tail -f /tmp/log/passwall2.log

# Строки относящиеся к hpwnr
grep hpwnr /tmp/log/passwall2.log

# Проверить hpwnr вручную
hpwnr help
hpwnr happ://crypt5/ВАШ_ТОКЕН
```

---

## Структура репозитория

```
passwall2-hpwnr-patch/
├── README.md
├── install.sh                     ← единственный скрипт для установки и удаления
└── files/
    ├── hpwnr.lua                  ← Lua-модуль (архитектуронезависимый)
    ├── passwall2-hpwnr-patch      ← скрипт патча/снятия патча
    └── hpwnr/
        └── x86_64
```

---

## Лицензия

Предоставляется как есть, без гарантий. Используйте только для легального анализа, обеспечения совместимости, исследований и обучения, и только с данными, к которым у вас есть право доступа. Названия Happ, V2RayTun и связанные с ними могут быть защищены правами третьих лиц; данный проект не связан с их владельцами.

---

## Благодарности

- [hpwnr](https://github.com/Omegaplexx/hpwnr)
- [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2)