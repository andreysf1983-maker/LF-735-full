# LEGIONFORGE 7.3.5 (build 26124) — патч-сет 2026-10-10

Репозиторий: `https://github.com/andreysf1983-maker/legionforge_111026.git` (клон без изменений) +
патчи под кастомный клиент (UWoW-подобная сборка 7.3.5 build 26124 с контентом BfA).

Все правки внесены **идемпотентными** скриптами из `patchkit/` — их можно
перезапускать, они не ломают уже применённые изменения:

```bat
python patchkit\patch_core.py     .
python patchkit\patch_scripts.py  .
```

---

## 1. Ошибка извлечения карт (`extract_maps.bat` → пункт 2, шаг vmaps)

**Было**

```
vmap4extractor.exe : Can't open World\Maps\test\test.wdt: FILE_NOT_FOUND
D:\legionforge\extract_delta.ps1:119 знак:9
+         & $tools.vmap4extractor -d $ClientDir 2>&1 | Out-Null
    + FullyQualifiedErrorId : NativeCommandError
```

**Причины (две, независимые)**

1. `extract_delta.ps1` работает при `$ErrorActionPreference = 'Stop'`. В Windows
   PowerShell 5.1 строка, попавшая в **stderr** внешней программы и перенаправленная
   через `2>&1` в конвейер, становится `ErrorRecord` → `NativeCommandError` →
   исключение → скрипт обрывается на первом же предупреждении.
2. `vmap4extractor` писал в **stderr** о штатной ситуации: у dev/test-карты
   `test` есть запись в `Map.db2`, но нет `.wdt`/геометрии в CASC.

**Стало**

* `core/src/tools/vmap4_extractor/wdtfile.cpp` — `CASCFile(..., warnNoExist = false)`;
  диагностика переведена в **stdout**: `Skipping map 'test': no WDT in the client storage (dev/test map)`.
* `core/src/tools/vmap4_extractor/vmapexport.cpp` — счётчик и сводка
  `[INFO] Skipped N map(s) without WDT ...`; извлечение продолжается по остальным картам.
* `extract_delta.ps1` — новая `Invoke-LfTool`: временно `EAP = 'Continue'`,
  разворачивает `ErrorRecord` в текст, фильтрует штатные сообщения
  (`FILE_NOT_FOUND`, `Can't open *.wdt`, `Skipping map`), пишет вывод в
  `server\logs\extract_delta_*.log` и **возвращает** код возврата. Все четыре
  вызова инструментов переведены на неё.
* `extract_delta.ps1` — каталоги staging (`maps/dbc/Cameras/gt/Buildings/vmaps/mmaps`)
  создаются до запуска инструментов; шаг vmaps обёрнут в `try/catch` (сбой не
  отменяет уже скопированные maps/dbc); mmaps считаются только при нулевом коде;
  в `reports/extract_delta.json` добавлены `FailedMmaps` и `IgnoredToolLines`.
* `extract_maps.ps1` — не требовал правок: там запуск идёт через
  `Start-Process -RedirectStandardOutput/-RedirectStandardError` (stderr не
  попадает в конвейер, `NativeCommandError` невозможен).

---

## 2. `bnetserver`: Failed to initialize SSL context

**Причины.** Настоящая ошибка писалась в категорию лога `server.ssl`, которой не
было в `bnetserver.conf`, поэтому в консоль уходила только общая строка. По сути
варианты три: (а) `CertificatesFile = "./bnetserver.cert.pem"` — путь
относительно **текущего каталога процесса**, а не exe; (б) `.pem` не скопированы
в каталог сборки; (в) сертификат и ключ от разных пар.

Штатная пара из репозитория проверена: RSA-2048, `sha256WithRSAEncryption`,
срок 2016→2036, публичные ключи сертификата и ключа совпадают.

**Стало**

* `core/src/server/bnetserver/Server/SslContext.cpp` — переписан:
  * разрешение путей по цепочке каталогов (конфиг → CWD → каталог `bnetserver.exe`
    → `..` → `../server`);
  * проверка соответствия пары `X509_check_private_key`;
  * автогенерация самоподписанной пары при отсутствии/рассинхроне
    (RSA-2048, SHA-256, 10 лет; `EVP_RSA_gen` для OpenSSL 3.x, fallback для 1.1.x);
  * вывод очереди ошибок OpenSSL (`ERR_error_string_n`) в лог;
  * ключ `SSLCertAutoGenerate` (1 = генерировать, 0 = падать как раньше).
* `core/src/server/bnetserver/Main.cpp` — к общей ошибке добавлена подсказка.
* `server/bnetserver.conf.dist` — `SSLCertAutoGenerate = 1`,
  `Logger.server.ssl=3,Console Bnet`, `Logger.server.bnetserver=3,Console Bnet`.
* `tools/ensure_ssl_cert.ps1` (новый) — префлайт: наличие, соответствие пары
  (сравнение публичных ключей), алгоритм подписи (SHA-1/MD5 отклоняются
  OpenSSL 3.x при SECLEVEL ≥ 1), срок действия; при проблеме — `*.bak-<дата>` и
  новая пара. Идемпотентен.
* `play.bat` — вызывает префлайт перед стартом `bnetserver.exe`.

---

## 3. `Missing name Guild.SaveInterval in config file`

`server/worldserver.conf.dist` ключ содержит (`Guild.SaveInterval = 15`), а живой
`server/worldserver.conf` создан из более старого дистрибутива.

**Стало:** `tools/ensure_conf_keys.ps1` (новый) — сравнивает наборы ключей
`.dist` и живого `.conf` и дописывает **все** отсутствующие (значения по
умолчанию из `.dist`); существующие значения не трогает; делает
`*.conf.bak-<дата>`; отчёт `reports/ensure_conf_keys.json`; режим `-WhatIfMode`.
Вызов встроен в `play.bat`, поэтому класс ошибок «Missing name …» закрыт
системно, а не только для `Guild.SaveInterval`.

---

## 4. Кастомные расы 31..44 (ядро + БД)

Подробно: `docs/CUSTOM_RACES_31_44.md`.

| # | Блокер | Правка |
|---|--------|--------|
| 1 | `MAX_RACES 31` | `45`, константы `RACE_CUSTOM_31..44`, `RACE_CUSTOM_FIRST/LAST` |
| 2 | `RACEMASK_*` из `(1 << (race-1))` — при race ≥ 33 UB и молчаливый 0 | все маски на 64 бита (`UI64LIT`), `RaceMaskForRace()`, `RACEMASK_CUSTOM_PLAYABLE`, скобки в `RACEMASK_HORDE` |
| 3 | `ObjectMgr::LoadPlayerCreateInfo` требует запись в `ChrRaces.db2` | расы из реестра кастомных рас принимаются; `displayId_m/f` берутся у расы-донора (иначе null-deref) |
| 4 | `LoadRaceAndClassExpansionRequirements` отбрасывает расы без DBC | то же правило; без него `CHAR_CREATE_FAILED` |
| 5 | `TeamForRace/TeamIdForRace/setFactionForRace` читают только DBC | реестр `CustomRaces.Definitions`: команда + раса-донор для `FactionID` |
| 6 | `racemask` в `playercreateinfo_spell_custom` / `playercreateinfo_cast_spell` читался как `uint32` | `GetUInt64`, `UI64LIT(1)`, лог `UI64FMTD`; колонки в БД → `BIGINT UNSIGNED` |
| 7 | «Заполнение дыр» `player_levelstats` пропускало расы без DBC | учитывает реестр (иначе нулевые статы на уровнях 2+) |

Конфигурация (`worldserver.conf`):

```ini
CustomRaces.Enable = 1
CustomRaces.Definitions = "31:ALLIANCE:1,32:HORDE:2,33:ALLIANCE:4,34:ALLIANCE:3,35:HORDE:5,36:HORDE:6,37:ALLIANCE:7,38:HORDE:8,39:HORDE:10,40:ALLIANCE:11,41:ALLIANCE:22,42:HORDE:9,43:NEUTRAL:24,44:ALLIANCE:27"
```

Формат записи `raceId:team:baseRace`, где `baseRace` — донор из `ChrRaces.db2`
(его `FactionID` и display id применяются к кастомной расе).

SQL: `sql/52_custom_races_31_44.sql` (+ `_rollback`).

---

## 5. Порядок применения

```bat
rem 1. Пересобрать ядро и инструменты (MAX_RACES - константа компиляции,
rem    vmap4extractor меняется в части stderr)
build_server.bat

rem 2. Синхронизировать конфиги и SSL-пару
powershell -NoProfile -ExecutionPolicy Bypass -File tools\ensure_conf_keys.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\ensure_ssl_cert.ps1

rem 3. Включить кастомные расы в world
tools\mysql\server\bin\mysql.exe -uroot world < sql\52_custom_races_31_44.sql

rem 4. Доизвлечь данные кастомного клиента
extract_maps.bat   ->  2

rem 5. Запуск
play.bat
```

Признак успеха в логе worldserver:

```
>> Registered 14 custom client race(s) (ids 31-44) from CustomRaces.Definitions
```

---

## 6. Известные ограничения

* Маски рас в колонках `INT UNSIGNED` (`spell_area.racemask`,
  `mail_level_reward.raceMask`, `quest_template.AllowableRaces`,
  `conditions.ConditionValue1`) физически не адресуют расы 33..44. Для таких
  механик расы 33+ трактуются как «любые» (маска 0). Точечная привязка требует
  перевода колонок на `BIGINT` и правки соответствующих загрузчиков.
* Серверный `ChrRaces.db2` подменять клиентским нельзя без
  `tools\check_db2_build.ps1`: при несовпадении `LayoutHash`/`MaxId` ядро падает
  по `ASSERT`. Поэтому расы 31..44 и описаны конфигом, а не подменой DBC.
