# LegionForge 7.3.5 (26124) — доработка проекта

Базовый репозиторий склонирован без изменений, сверху добавлены правки ниже.

## 1. Кастомный клиент: данные клиента больше не игнорируются

**Проблема.** `extract_maps.bat` печатал «[OK] server\data уже содержит
проверенные maps, dbc и vmaps. Извлечение пропущено» и выходил. Проверка
`check_game_data.ps1` смотрит только на сервер (количество плиток, `Map.db2`,
`*.vmtree`) и никогда не открывает клиент. На кастомном клиенте (UWoW с
расами BfA и картами новых дополнений) весь кастом оставался неизвлечённым.

**Решение.**

| Файл | Назначение |
|------|-----------|
| `tools/lf_db2.ps1` | чтение заголовков DB2 (WDC1/WDC2/WDC3), справочник рас, парсер enum `Races` из `SharedDefines.h` |
| `check_client_delta.ps1` | снимает из клиента только db2 (`mapextractor -e 2`), сравнивает с `server\data\dbc`, находит недостающие/изменённые db2, кастомные расы и классы, расхождение `Map.db2`; пишет `reports/client_delta.json` и `.md`; коды выхода 0/2/3 |
| `extract_delta.ps1` | доизвлечение: распаковка во временную папку и копирование в `server\data` **только недостающих** файлов (maps, dbc, Cameras, gt, vmaps), генерация mmaps только для новых карт, отчёт `reports/extract_delta.json` |
| `extract_maps.bat` | вместо «пропущено» — дельта-проверка и меню: ничего не делать / доизвлечь недостающее / полное переизвлечение |
| `sql/50_uwow_custom_races.sql` | включение рас 31, 32, 34, 35, 36, 37: стартовые позиции, `player_levelstats`, предметы, заклинания, панель команд, снятие гейта дополнения |
| `sql/50_uwow_custom_races_rollback.sql` | откат |
| `docs/CUSTOM_CLIENT_UWOW.md` | полный разбор: что проверяется, почему изменённые db2 не подменяются автоматически, что нужно от ядра |

Изменённые db2 **не перезаписываются**: они складываются в
`server\data\dbc_client_delta`, потому что ядро сверяет `LayoutHash` и `MaxId`
и падает по `ASSERT` при расхождении (`DB2Stores.cpp`).

## 2. Порядок в папке server: журналы и падения

| Файл | Изменение |
|------|-----------|
| `server/worldserver.conf.dist`, `server/bnetserver.conf.dist` | `LogsDir = "logs"` вместо `""` |
| `patch_conf_paths.ps1` | прописывает абсолютный `…\server\logs` в рабочие conf, создаёт `logs`, `logs\gm`, `Crashes` |
| `tidy_server_dirs.ps1` | создаёт папки, переносит уже лежащие в корне `*.log` и отчёты/дампы падений, чистит старше `-KeepDays` (30 суток) |
| `play.bat` | вызывает `tidy_server_dirs.ps1` перед стартом |
| `docs/LOGS_AND_CRASHES.md` | описание схемы |

Итог: `server\logs\*` — журналы, `server\Crashes\*` — `.txt` и `.dmp`,
корень `server` — только exe/dll/conf/data.

## 3. Панель управления (web)

В комплект добавлено веб-приложение (Next.js + PostgreSQL + Drizzle):
дашборд состояния данных, таблица дельты клиента, каталог кастомных рас с
готовым SQL, карта журналов и падений, импорт отчётов
`reports/client_delta.json` через `POST /api/delta/import`.


## 2026-10-10 — кастомный клиент build 26124: расы 31..44, извлечение карт, SSL bnetserver

Патчеры: `patchkit/patch_core.py`, `patchkit/patch_scripts.py` (идемпотентны).

### Ядро
* `MAX_RACES` 31 → 45, добавлены `RACE_CUSTOM_31..44`, `RACE_CUSTOM_FIRST/LAST`.
* Все `RACEMASK_*` переведены на 64 бита (`UI64LIT`): сдвиг `1 << (race-1)` при
  race ≥ 33 был неопределённым поведением и молча давал 0. Добавлены
  `RaceMaskForRace()`, `RACEMASK_CUSTOM_PLAYABLE`, `RACEMASK_DB32_LIMIT`,
  восстановлены скобки в `RACEMASK_HORDE`.
* Реестр кастомных рас (`CustomRaces.Enable` / `CustomRaces.Definitions` в
  `worldserver.conf`): команда, раса-донор для `FactionID` и `displayId`.
  Новые методы `Player::IsCustomRace/GetCustomRaceBase/GetCustomRaceTeam`.
* `ObjectMgr`: `playercreateinfo`, `race_unlock_requirement` и заполнение дыр
  `player_levelstats` больше не отбрасывают расы 31..44; `displayId` берётся у
  расы-донора (устранён потенциальный null-deref); `racemask` читается как
  `uint64`, формат лога — `UI64FMTD`.
* `CharacterHandler`: создание персонажа и смена фракции работают с 64-битными
  масками и расами реестра.
* `CriteriaHandler`, `ConditionMgr`: 64-битные racemask-проверки, корректный каст.
* `bnetserver/Server/SslContext.cpp` переписан: поиск `.pem` по цепочке
  каталогов, проверка соответствия пары, автогенерация самоподписанного
  сертификата (RSA-2048/SHA-256, OpenSSL 3.x), вывод очереди ошибок OpenSSL,
  ключ `SSLCertAutoGenerate`.
* `vmap4extractor`: отсутствие `.wdt` (dev/test-карты) больше не пишется в
  stderr — сообщение в stdout, счётчик и сводка пропущенных карт.

### Обвязка
* `extract_delta.ps1`: функция `Invoke-LfTool` (защита от `NativeCommandError`
  при `$ErrorActionPreference = 'Stop'`), фильтрация штатных сообщений,
  предварительное создание каталогов staging, `try/catch` вокруг шага vmaps,
  честный подсчёт mmaps, поля `FailedMmaps`/`IgnoredToolLines` в
  `reports/extract_delta.json`.
* `extract_maps.ps1`: та же защита в обёртке запуска инструментов.
* `play.bat`: префлайт `tools\ensure_conf_keys.ps1` + `tools\ensure_ssl_cert.ps1`
  перед стартом `bnetserver.exe`.
* Новые инструменты: `tools\ensure_ssl_cert.ps1`, `tools\ensure_conf_keys.ps1`.
* Конфиги: `SSLCertAutoGenerate`, `Logger.server.ssl`, `Logger.server.bnetserver`
  в `bnetserver.conf.dist`; секция `CustomRaces.*` в `worldserver.conf.dist`.
* SQL: `sql/52_custom_races_31_44.sql` (+ `_rollback`) — `BIGINT` racemask,
  стартовые данные для рас 31..44, `race_unlock_requirement.expansion = 6`,
  контрольный отчёт.
* Документация: `docs/CUSTOM_RACES_31_44.md`, `docs/EXTRACTOR_SSL_FIXES.md`.
