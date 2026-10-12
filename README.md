# LEGIONFORGE 7.3.5 (build 26124)

Серверная платформа World of Warcraft: Legion 7.3.5.

## Быстрый старт (Windows)
1. Положите в `sql\base\` только `auth.sql` и `characters.sql`. Чистые ADB `world`/`hotfixes` загрузятся автоматически, если соответствующие базы пусты (см. `docs\ADB_DATABASES.md`).
2. Если карты уже извлечены, скопируйте содержимое папки `data` в `server\data` (см. `docs\SETUP_DATA.md`). Если нет - положите клиент 7.3.5 в `WoW_Client\` или укажите путь, когда setup его запросит.
3. Запустите `UNBLOCK.bat` один раз, затем `setup.bat` от имени администратора.
4. `play.bat` - запуск bnetserver, worldserver и клиента.

`setup.bat` проверяет `server\data` до поиска клиента: требуется не менее 200 файлов `maps\*.map`, покрытие обязательных континентов Vanilla–Legion, `dbc\Map.db2` и не менее 50 `vmaps\*.vmtree`. При готовых картах поиск клиента и повторное извлечение пропускаются. `mmaps` рекомендуются для движения NPC, но необязательны. Для игрового мира setup скачивает чистый ADB_735.10 автоматически; 7-Zip не нужен для его RAR-распаковки - используется проверенный RARLAB UnRAR.

## Учётные записи
Если при создании аккаунта появляется `Unknown column ...`, запустите `setup.bat` или `create_account.bat` заново: схема `auth` будет проверена и дополнена (см. `docs\ACCOUNTS.md`).

## Сервер собран, но не запускается
См. `docs\SERVER_START.md`. `play.bat` теперь проверяет DLL (`check_server_runtime.ps1`) и копирует недостающие библиотеки; отчёт - `server\runtime_check.txt`.

## Чистые базы ADB
Если `world` или `hotfixes` пусты, `setup.bat` скачивает официальный архив AshamaneCore ADB_735.10 (~84 МиБ), проверяет SHA-256 и автоматически распаковывает его в `sql\base\ADB_world.sql` и `ADB_hotfixes.sql`. Большие локальные `world.sql`/`hotfixes.sql` не требуются. Источник - ADB_735.10 Final before BfA, не точный snapshot build 26124; детали и размеры: `docs\ADB_DATABASES.md`.

## Если worldserver упал или не запускается
`docs\CRASH-DIAGNOSIS.md` - подтверждённая причина: ASSERT при загрузке DB2
(`BATTLE_PET_SPECIES_MAX_ID (2164) must be equal to or greater than 5004`), то есть `server\data`
не от чистого клиента 7.3.5 build 26124. Проверка без запуска сервера:
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_db2_build.ps1`
(встроена в `play.bat` и `setup.bat`). Дальше либо `extract_maps.bat` из своего клиента, либо
`tools\set_pet_species_max_id.ps1 -Value 5004` и пересборка.
Release теперь собирается с PDB-символами, ASSERT пишет свой текст в breadcrumb крэш-отчёта,
адреса старых логов расшифровывает `tools\resolve_crash.ps1`.

## Что отключено и что можно включить
`docs\FEATURE-AUDIT.md` - аудит по коду и данным ADB: союзные расы Legion (27-30) были закрыты
гейтом дополнения и теперь включаются патчами `sql\48_legion_allied_races.sql`,
`sql\49_legion_allied_races_hotbar.sql` и одной строкой ядра (нужна пересборка). Харанир, Вульперы и
Механогномы на клиенте 26124 невозможны: их нет в `ChrRaces.db2` и CASC клиента. Проверить свой клиент:
`python tools\legion_db2\audit_races_forms.py` (отчёт `logs\race_form_audit.md`).

## Иконка серверов
`core\ico\server.ico` встраивается в `bnetserver.exe` и `worldserver.exe` при компиляции
(`core\src\server\*\*.rc`, ресурс `IDI_APPICON`).

## Скрипты запуска и кодировка
Все `.bat` хранятся в CP866 с окончаниями CRLF, все `.ps1` — в UTF-8 с BOM. Не пересохраняйте их
в редакторе в UTF-8/LF. Если правили скрипты — выполните `python tools\normalize_scripts.py`.
Подробности — `docs\BAT_FIX.md`.

## Доработка 2026 (см. CHANGELOG_IMPROVEMENTS.md)

- `check_client_delta.ps1` — сверка вашего клиента с `server\data` (кастомные расы, новые карты, свои db2).
- `extract_delta.ps1` — доизвлечение ТОЛЬКО недостающего, ничего не затирая.
- `extract_maps.bat` — вместо «Извлечение пропущено» предлагает дельта-доизвлечение.
- `sql/50_uwow_custom_races.sql` — включение рас 31/32/34/35/36/37 кастомного клиента.
- `tidy_server_dirs.ps1` + `LogsDir = "logs"` — журналы в `server\logs`, падения в `server\Crashes`.
- `docs/CUSTOM_CLIENT_UWOW.md`, `docs/LOGS_AND_CRASHES.md` — подробные инструкции.
