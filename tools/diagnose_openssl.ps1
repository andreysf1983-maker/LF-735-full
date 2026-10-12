<#
.SYNOPSIS
    LEGIONFORGE 7.3.5 - диагностика фатального выхода bnetserver/worldserver
    из-за "OPENSSL_Uplink(...): no OPENSSL_Applink".

.DESCRIPTION
    Симптом: окно сервера печатает баннер, затем одну строку
        OPENSSL_Uplink(00007FFFB2656C58,08): no OPENSSL_Applink
    и сразу закрывается ("Для продолжения нажмите любую клавишу").
    Крэш-дампа нет, в логе пусто - процесс убит внутри libcrypto до инициализации.

    Механика. Динамический OpenSSL (libcrypto-3-x64.dll) и exe собраны с РАЗНЫМИ
    CRT, поэтому DLL не может звать stdio напрямую: она берёт указатели из таблицы
    OPENSSL_ApplinkTable, которую обязано заполнить приложение функцией
    OPENSSL_Applink(). Если экспорта нет, OPENSSL_Uplink() вызывает OPENSSL_die().

    Что проверяет скрипт:
      1. Есть ли в exe экспорт OPENSSL_Applink (т.е. скомпилирован ли фикс
         #include <openssl/applink.c> из core\src\server\*\Main.cpp).
      2. Какие DLL OpenSSL лежат рядом с exe (это то, что реально загрузится).
      3. Нет ли в PATH посторонних libcrypto/libssl, которые могут перекрыть
         локальные (Git for Windows, PostgreSQL, Steam, старые сборки OpenSSL).
      4. Валидна ли переменная OPENSSL_CONF (невалидный путь - частый триггер
         первой же записи в stderr из DLL).

.PARAMETER ServerDir
    Каталог с bnetserver.exe и worldserver.exe. По умолчанию ..\server.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\diagnose_openssl.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\diagnose_openssl.ps1 -ServerDir D:\legionforge\server
#>
param(
    [string]$ServerDir = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
if (-not $ServerDir) { $ServerDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'server' }

$script:ExitCode = 0
function Say([string]$Text, [string]$Color = 'Gray') {
    if ($Quiet) { return }
    Write-Host $Text -ForegroundColor $Color
}
function Fail([string]$Text) { Say "  [ОШИБКА] $Text" 'Red';    $script:ExitCode = 1 }
function Warn([string]$Text) { Say "  [!] $Text" 'Yellow'; if ($script:ExitCode -eq 0) { $script:ExitCode = 2 } }
function Ok([string]$Text)   { Say "  [OK] $Text" 'Green' }

Say '  == LEGIONFORGE: диагностика OpenSSL / OPENSSL_Applink =='
Say "  Каталог сервера: $ServerDir"

if (-not (Test-Path -LiteralPath $ServerDir)) {
    Fail "Каталог $ServerDir не найден."
    exit $script:ExitCode
}

# ---------------------------------------------------------------------------
# 1. Проверка экспорта OPENSSL_Applink в каждом exe
# ---------------------------------------------------------------------------
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$needle = 'OPENSSL_Applink'

foreach ($exeName in @('bnetserver.exe', 'worldserver.exe')) {
    $exePath = Join-Path $ServerDir $exeName
    if (-not (Test-Path -LiteralPath $exePath)) {
        Say "  [$exeName] не найден - пропуск (соберите сервер: build_server.bat)" 'DarkGray'
        continue
    }

    Say ''
    Say "  --- $exeName ---" 'Cyan'

    $hasExport = $false
    try {
        $bytes = [System.IO.File]::ReadAllBytes($exePath)
        $text  = $latin1.GetString($bytes)
        $hasExport = $text.IndexOf($needle, [System.StringComparison]::Ordinal) -ge 0
        $bytes = $null
        $text  = $null
    } catch {
        Warn "Не удалось прочитать $exeName : $($_.Exception.Message)"
    }

    if ($hasExport) {
        Ok "экспорт OPENSSL_Applink присутствует - фикс скомпилирован в exe."
    } else {
        Fail "в exe НЕТ экспорта OPENSSL_Applink. Именно это даёт '$needle' -> OPENSSL_die()."
        Say '        Исправление уже есть в исходниках:' 'Yellow'
        Say '          core\src\server\bnetserver\Main.cpp'   'Yellow'
        Say '          core\src\server\worldserver\Main.cpp'  'Yellow'
        Say '        там добавлено #include <openssl/applink.c>.' 'Yellow'
        Say '        Пересоберите сервер:  build_server.bat' 'Yellow'
        Say '        До пересборки помогает временное смягчение (см. пункт 4 ниже).' 'Yellow'
    }
}

# ---------------------------------------------------------------------------
# 2. DLL OpenSSL рядом с exe
# ---------------------------------------------------------------------------
Say ''
Say '  --- DLL OpenSSL рядом с сервером ---' 'Cyan'
$localDlls = @(Get-ChildItem -LiteralPath $ServerDir -Filter '*.dll' -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match '^(libcrypto|libssl)' })
if ($localDlls.Count -eq 0) {
    Say '  Локальных libcrypto/libssl нет: OpenSSL статически влинкован в exe.' 'DarkGray'
    Say '  Тогда uplink-таблица не нужна и строка про OPENSSL_Applink означала бы' 'DarkGray'
    Say '  загрузку ПОСТОРОННЕЙ DLL из PATH - смотрите пункт 3.' 'DarkGray'
} else {
    foreach ($d in $localDlls) {
        $ver = ''
        try { $ver = $d.VersionInfo.FileVersion } catch { }
        Ok ("{0}  (версия {1}, {2:N0} байт)" -f $d.Name, $(if ($ver) { $ver } else { 'н/д' }), $d.Length)
    }
    $crypto = @($localDlls | Where-Object { $_.Name -match '^libcrypto' })
    $ssl    = @($localDlls | Where-Object { $_.Name -match '^libssl' })
    if ($crypto.Count -ne $ssl.Count) {
        Warn 'libcrypto и libssl присутствуют не в паре - возможны конфликты версий.'
    }
}

# ---------------------------------------------------------------------------
# 3. Посторонние OpenSSL DLL в PATH (перекрывают локальные)
# ---------------------------------------------------------------------------
Say ''
Say '  --- Поиск посторонних OpenSSL DLL в PATH ---' 'Cyan'
$foundForeign = 0
if ($env:PATH) {
    foreach ($dir in ($env:PATH -split ';')) {
        if (-not $dir) { continue }
        $dir = $dir.Trim()
        if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
            try {
                $hits = @(Get-ChildItem -LiteralPath $dir -Filter '*.dll' -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -match '^(libcrypto|libssl)' })
                foreach ($h in $hits) {
                    Warn ("PATH содержит {0}  ->  {1}" -f $h.Name, $dir)
                    $foundForeign++
                }
            } catch { }
        }
    }
}
if ($foundForeign -eq 0) {
    Ok 'в PATH посторонних libcrypto/libssl не найдено.'
} else {
    Say '        Windows грузит DLL из каталога exe ПЕРЕД PATH, поэтому локальные' 'Yellow'
    Say '        файлы обычно побеждают. Но если локальных DLL нет (статическая' 'Yellow'
    Say '        сборка), загрузится посторонняя - от Git, PostgreSQL или Steam.' 'Yellow'
}

# ---------------------------------------------------------------------------
# 4. OPENSSL_CONF
# ---------------------------------------------------------------------------
Say ''
Say '  --- Переменная OPENSSL_CONF ---' 'Cyan'
$cnf = $env:OPENSSL_CONF
$bundled = Join-Path $PSScriptRoot 'openssl.cnf'
if (-not $cnf) {
    Warn 'OPENSSL_CONF не задана. OpenSSL ищет конфиг по встроенному пути сборки;'
    Say  '        если тот путь не существует, первая же запись в stderr из DLL' 'Yellow'
    Say  '        приводит к фатальному uplink-выходу.' 'Yellow'
} elseif (Test-Path -LiteralPath $cnf) {
    Ok "OPENSSL_CONF задана и файл существует: $cnf"
} else {
    Fail "OPENSSL_CONF указывает на НЕСУЩЕСТВУЮЩИЙ файл: $cnf"
}

if (Test-Path -LiteralPath $bundled) {
    Say ''
    Say '  Временное смягчение БЕЗ пересборки (не заменяет фикс в Main.cpp):' 'Cyan'
    Say "      set `"OPENSSL_CONF=$bundled`"" 'White'
    Say '  play.bat подставляет этот путь автоматически, если OPENSSL_CONF пуста' 'Gray'
    Say '  или указывает на несуществующий файл.' 'Gray'
} else {
    Warn "Не найден штатный конфиг $bundled"
}

Say ''
if ($script:ExitCode -eq 0) {
    Ok 'Признаков проблемы OPENSSL_Applink не обнаружено.'
} elseif ($script:ExitCode -eq 1) {
    Fail 'Требуется пересборка сервера (build_server.bat) - фикс уже в исходниках.'
} else {
    Warn 'Есть предупреждения; если сервер всё равно падает с no OPENSSL_Applink - пересоберите его.'
}

exit $script:ExitCode
