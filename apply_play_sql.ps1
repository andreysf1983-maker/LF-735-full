param(
    [string]$Root = "",
    [string]$MysqlExe = "",
    [string]$CnfPath = "",
    [switch]$QuestOnly
)

$ErrorActionPreference = "Continue"
if (-not $Root) { $Root = $PSScriptRoot }
if (-not $CnfPath) { $CnfPath = Join-Path $Root "setup_tmp\mysql.cnf" }
if (-not $MysqlExe) {
    $MysqlExe = & (Join-Path $Root "find_mysql.ps1") -Port 3306
}

if (-not $MysqlExe -or -not (Test-Path $MysqlExe)) {
    Write-Host "  [!] mysql.exe not found"
    exit 1
}
if (-not (Test-Path $CnfPath)) {
    Write-Host "  [!] $CnfPath not found - run setup.bat first"
    exit 1
}

$sqlDir = Join-Path $Root "sql"
# База персонажей называется `characters`: именно её создаёт setup.bat и именно её прописывает mysql_helper.ps1
# в worldserver.conf. Раньше здесь стояло `legion_characters` (имя с компьютера автора) - патчи персонажей
# падали с "Unknown database".
$charDb = "characters"
$patches = @(
    # Remove two accidentally-added duplicate columns before worldserver prepares its instance query.
    @{ Db = $charDb; Rel = "updates\characters\master\2026_01_01_02_character_instance_join_fix.sql" },
    @{ Db = $charDb; File = "04_fix_instance_data.sql" },
    @{ Db = $charDb; File = "31_remove_bots_characters.sql" },
    @{ Db = $charDb; Rel = "stitch\010_scenario_return_characters.sql" },
    @{ Db = "world";      File = "31_remove_bots_world.sql" },
    @{ Db = "world";      File = "02_custom_creatures.sql" },
    @{ Db = "world";      File = "07_legion_instance_template.sql" },
    @{ Db = "world";      File = "08_all_instance_template.sql" },
    @{ Db = "world";      File = "09_lfg_dungeon_entrances.sql" },
    @{ Db = "auth";       File = "10_legionforge_realm.sql" },
    @{ Db = "world";      File = "13_warlock_starter_pet.sql" },
    @{ Db = "world";      File = "15_young_and_vicious.sql" },
    @{ Db = "world";      File = "18_quest_item_target.sql" },
    @{ Db = "world";      File = "19_quest_generic_phase.sql" },
    # Патчи, которые раньше лежали в sql\ и нигде не применялись (проверены на чистой базе, идемпотентны):
    @{ Db = "world";      File = "20_imp_display.sql" },
    @{ Db = $charDb;      File = "20_imp_display_characters.sql" },
    @{ Db = "world";      File = "22_they_sent_assassins.sql" },
    @{ Db = "world";      File = "23_kill_target_questgivers.sql" },
    @{ Db = "world";      File = "24_neutral_kill_targets.sql" },
    @{ Db = "world";      File = "25_clear_promo_mail_world.sql" },
    @{ Db = $charDb;      File = "25_clear_promo_mail_characters.sql" },
    @{ Db = "world";      File = "26_welcome_sender.sql" },
    @{ Db = "world";      File = "27_worgen_start.sql" },
    @{ Db = "world";      File = "28_fel_imp_display.sql" },
    # Союзные расы Legion (27-30): гейт дополнения и стартовая панель умений.
    # Данные старта/статистика уже есть в ADB_735.10; патчи идемпотентны.
    @{ Db = "world";      File = "48_legion_allied_races.sql" },
    @{ Db = "world";      File = "49_legion_allied_races_hotbar.sql" },
    # [LEGIONFORGE AUDIT 2026-10] Кастомные расы клиента 31..44: патч раньше
    # НЕ подключался ни к одному установщику - расы появлялись в окне создания,
    # но playercreateinfo/player_levelstats/race_unlock_requirement оставались
    # пустыми (CHAR_CREATE_FAILED). 52_primary применяется после 48/49 и
    # является единственным источником истины о соответствии "раса -> донор".
    @{ Db = "world";      File = "52_custom_races_31_44.sql" }
)

if ($QuestOnly) {
    $patches = @(
        @{ Db = "world"; File = "18_quest_item_target.sql" },
        @{ Db = "world"; File = "19_quest_generic_phase.sql" }
    )
}

$generatedP05 = Join-Path $sqlDir "generated_p05_item_targets.sql"
if (Test-Path $generatedP05) {
    $patches += @{ Db = "world"; File = "generated_p05_item_targets.sql" }
}

$fail = 0
foreach ($p in $patches) {
    $path = if ($p.ContainsKey("Rel") -and $p.Rel) {
        Join-Path $sqlDir $p.Rel
    } else {
        Join-Path $sqlDir $p.File
    }
    $label = if ($p.ContainsKey("Rel") -and $p.Rel) { $p.Rel } else { $p.File }
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "  [!] required SQL patch is missing: $label"
        $fail++
        break
    }
    Write-Host "  [*] applying $label -> $($p.Db)..."
    # SQL передаётся в stdin побайтово: конвейер PowerShell (Get-Content | mysql) портит UTF-8/кириллицу
    # в Windows PowerShell 5.1 (кодировка $OutputEncoding = ASCII).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $MysqlExe
    $psi.Arguments = ('--defaults-extra-file="{0}" --default-character-set=utf8mb4 --max_allowed_packet=512M {1}' -f $CnfPath, $p.Db)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $bytes = [System.IO.File]::ReadAllBytes($path)
    try { $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length) } catch { }
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    $LASTEXITCODE = $proc.ExitCode
    foreach ($text in @($outTask.Result, $errTask.Result)) {
        if ($text) { ($text -split "`r?`n") | Where-Object { $_ } | ForEach-Object { Write-Host "      $_" } }
    }
    if ($LASTEXITCODE -ne 0) {
        $mysqlExitCode = $LASTEXITCODE
        Write-Host "  [!] FAIL $label (mysql exit $mysqlExitCode)"
        $fail++
        break
    } else {
        Write-Host "  [OK] $label"
    }
}

if ($fail -gt 0) {
    Write-Host "  [!] $fail SQL patch(es) failed"
    exit 1
}
exit 0
