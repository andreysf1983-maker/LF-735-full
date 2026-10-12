# LEGIONFORGE 7.3.5 build 26124 — исправления (сессия 2)
Репозиторий: https://github.com/andreysf1983-maker/7.3.5_FIXED_1.git (branch main, commit 53a7604)
В архиве полный клон, ВСЕ фиксы УЖЕ ПРИМЕНЕНЫ. Просто распакуйте и соберите.

## Запуск
```
build_server.bat
play.bat
```

## Исправление 1 — компиляция (error C3861)
DB2Stores.cpp:989 — TC_LOG_ERROR (макрос TrinityCore) -> LF_LOG_ERROR (родной логгер LegionForge).
Проверка: grep TC_ по core/src = 0.

## Исправление 2 — старт worldserver (ASSERT SpellMgr.cpp:2234)
```
SpellMgr::LoadSpellInfoStore ASSERTION FAILED:
  effect->Effect < TOTAL_SPELL_EFFECTS  "TOTAL_SPELL_EFFECTS must be at least 262"
```
Причина: SpellEffect.db2 этого билда содержит эффекты 256..261, а в ядре было 256.
Поднять одну константу НЕДОСТАТОЧНО: два массива-обработчика объявлены как
[TOTAL_SPELL_EFFECTS] и имели ровно 256 элементов. Остальные стали бы nullptr,
а Spell.cpp делает (this->*SpellEffects[eff])() -> вызов нулевого указателя = краш.

Исправлено согласованно, 3 файла:
1. SharedDefines.h    : SPELL_EFFECT_256..261 + TOTAL_SPELL_EFFECTS = 262
2. SpellEffects.cpp   : +6 строк &Spell::EffectNULL (256..261)  -> массив 262
3. SpellInfo.cpp      : +6 строк {TARGET_NONE, TARGET_OBJECT_TYPE_NONE} -> массив 262
Контроль: все три числа равны 262.

## Исправление 3 — устойчивость загрузчика (профилактика)
SpellMgr.cpp: 5 жёстких ASSERT заменены на «залогировать и пропустить строку»
(Effect, EffectAura, ImplicitTarget[0..1], EffectIndex). Теперь одна грязная строка
db2 не роняет старт, а пишет в лог номер заклинания и нужное значение константы.

DB2Stores.cpp: та же защита для PvpTalent, PvpTalentUnlock и Talent
(class/tier/column) — индексы массивов остаются валидными.

## Константы под клиент 26124 (проверены)
- TOTAL_SPELL_EFFECTS=262 (+ оба массива 262)
- MAX_BATTLEGROUND_BRACKETS=13, BATTLE_PET_SPECIES_MAX_ID=5004
- MAX_DIFFICULTY=148 (+clamp сдвига), TaxiMaskSize=286 (+fill(0))
- MAX_RACES=45, RACEMASK 64-бит
- TOTAL_AURAS=492, TOTAL_SPELL_TARGETS — в норме, защита добавлена

## Если снова ASSERT "must be at least N"
Теперь вместо падения будет строка в логе. Поднимите константу до N
и ОБЯЗАТЕЛЬНО добавьте столько же элементов в соответствующий массив-обработчик.
