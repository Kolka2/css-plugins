# nadepractice — gamedata: что это и как восстановить после обновления игры

[English version below](#english)

`nadepractice` почти всё делает средствами SourceMod, но одной функции без gamedata нет: **настоящая детонация снарядов повтора** (`!last`, `!show`). Для неё плагин вызывает функции игры `CHEGrenadeProjectile::Create`, `CFlashbangProjectile::Create`, `CSmokeGrenadeProjectile::Create`. Адреса этих функций описаны в файле `gamedata/nadepractice.games.txt`.

После обновления игры адреса могут измениться. Тогда плагин **не ломается**: он пишет в лог ошибок одну строку на каждую функцию и дальше работает с запасным вариантом — детонацией плагином (флешка повтора не слепит, взрыв HE только картинкой). Эта инструкция — как вернуть функцию самому, без ИИ-помощников и, возможно, без интернета.

Длительность дыма (меню «Длительность дыма») gamedata не требует.

## Как понять, что gamedata сломалась

- В логе ошибок SourceMod (`addons/sourcemod/logs/errors_*.log`) строка вида:
  `[nadepractice] Feature "real replay detonation (HE)" is disabled: gamedata is out of date (signature "CHEGrenadeProjectile::Create" not found). ... docs/nadepractice/GAMEDATA.md, section "CHEGrenadeProjectile::Create".`
- Команда `sm_nadepractice_gamedata` в консоли сервера: у каждой функции `ok` или `off: <причина>`.
- Строка при загрузке плагина в обычном логе: `[nadepractice] <версия>, nadethrow: ..., gamedata: he ok, flash ok, smoke off`.

Причины:
- `gamedata file ... not found` — файл не скопирован на сервер (раздел «Установка» ниже);
- `signature "..." not found` — подпись не совпала: игра обновилась (разделы по функциям ниже);
- `the call could not be prepared` — ошибка в файле gamedata (опечатка в подписи, лишняя кавычка);
- `the check failed` — подпись нашла **не ту** функцию: вызов вернул не снаряд. Функция выключена до перезапуска плагина; подпись нужно сделать заново.

## Установка

`gamedata/nadepractice.games.txt` → `cstrike/addons/sourcemod/gamedata/nadepractice.games.txt`. После замены файла — `sm plugins reload nadepractice` или смена карты.

## Что держать скачанным заранее

На случай, если в момент обновления не будет интернета:

1. **Ghidra** (бесплатно, ghidra-sre.org; нужна Java 17+, её дистрибутив тоже скачать) или **IDA Free** (hex-rays.com). Подойдёт любая из двух.
2. Для Linux — утилиты `nm` и `objdump` (пакет `binutils`); на Windows они есть в Git for Windows / MSYS2 / MinGW.
3. **Копии бинарников сервера до обновления** — главное. Перед каждым обновлением игры сохраняйте:
   - `cstrike/bin/server.dll` (Windows, 32 бита, `srcds.exe`),
   - `cstrike/bin/x64/server.dll` (Windows, 64 бита, `srcds_win64.exe`),
   - `cstrike/bin/server_srv.so` (Linux, 32 бита),
   - `cstrike/bin/linux64/server_srv.so` (Linux, 64 бита),
   - и `cstrike/steam.inf` (строка `PatchVersion=` — версия игры).

   Старая версия нужна, чтобы сравнить: в ней функция уже найдена (адрес можно найти по текущей подписи), и в новой версии её проще узнать по тем же ориентирам.
4. Этот файл и `gamedata/nadepractice.games.txt` текущей версии.

## Четыре сборки сервера

| Ключ в gamedata | Сервер | Файл | Символы |
|---|---|---|---|
| `windows` | Windows, 32 бита | `cstrike/bin/server.dll` | нет: байтовая подпись |
| `windows64` | Windows, 64 бита | `cstrike/bin/x64/server.dll` | нет: байтовая подпись |
| `linux` | Linux, 32 бита | `cstrike/bin/server_srv.so` | есть: `@имя` |
| `linux64` | Linux, 64 бита | `cstrike/bin/linux64/server_srv.so` | есть: `@имя` |

Текущий файл сделан под `PatchVersion=11003710`.

## Linux: по символам

В Linux-сборках функции названы по именам, поэтому в gamedata стоит `@` и «искажённое» (mangled) имя. Проверить, что имя есть в новом бинарнике:

```
nm server_srv.so | grep CHEGrenadeProjectile6Create
nm server_srv.so | grep CFlashbangProjectile6Create
nm server_srv.so | grep CSmokeGrenadeProjectile6Create
```

Если имя изменилось (другие параметры), скопируйте новое из вывода `nm` (без адреса и буквы `t`) и поставьте перед ним `@`. Человекочитаемый вид — `nm -C`.

Если SourceMod не находит символ, хотя `nm` его показывает (символы локальные, буква `t`), — сделайте байтовую подпись так же, как для Windows.

## Windows: байтовая подпись

Подпись — первые байты функции, где байты, которые меняются от сборки к сборке (адреса и смещения вызовов), заменены на `\x2A` («любой байт»). SourceMod ищет эту последовательность в `server.dll`; она должна встречаться **ровно один раз**.

### Общий порядок

1. Откройте `server.dll` в Ghidra (File → Import File, затем двойной щелчок и «Analyze» с настройками по умолчанию; анализ идёт несколько минут). Для 64 бит — тот же порядок с `x64/server.dll`.
2. Найдите функцию по ориентирам (разделы ниже). Самый надёжный ориентир — строка с именем класса снаряда:
   Search → For Strings → фильтр `hegrenade_projectile` → двойной щелчок по строке → в окне листинга у строки есть список ссылок (XREF). Ссылок несколько: одна-две — регистрация класса (крошечные функции из пары инструкций), одна — сам `Create`, ещё одна-две — другой код (например, сравнение имён классов). `Create` узнаётся по началу (разделы ниже).
3. Удобный способ узнать функцию — **сравнить с Linux-сборкой той же разрядности**: откройте в другом окне `server_srv.so` (там функция подписана по имени) и сравните последовательность вызовов и чисел. Порядок одинаковый, отличаются только адреса.
4. Сделайте подпись: в листинге выделите первые 25–50 байт функции (до вызова `CBaseEntity::Create` включительно) и выпишите байты. Замените на `\x2A`:
   - 4 байта после `E8` (call) и `E9` (jmp) и после `0F 8x` (условный переход);
   - у 32 бит — 4 байта абсолютного адреса (например, после `68` = `push адрес строки`);
   - у 64 бит — 4 байта смещения в инструкциях с `[rip+...]` (например, `48 8D 0D xx xx xx xx` = `lea rcx, [rip+...]`).
5. Проверьте уникальность: Search → Memory → «Hex», введите подпись, где `\x2A` заменены на `.` (точку, режим regular expression) или на `??` (зависит от версии Ghidra). Должно найтись ровно одно место — начало нужной функции. Если мест больше — добавьте ещё байты в конец.
   В IDA Free: Search → Sequence of bytes, `2A` заменить на `?`.
6. Запишите подпись в `gamedata/nadepractice.games.txt` в нужный ключ (`windows` или `windows64`) в формате `"\x55\x8B\xEC..."`.

### Проверка результата

1. Скопировать файл на сервер, `sm plugins reload nadepractice`.
2. `sm_nadepractice_gamedata` — у функции `ok`.
3. Пункты чек-листа «Этап 14.2»: `!last` с флешкой слепит, HE взрывается, дым настоящий. Если вызов вернул не снаряд, функция выключится с причиной `the check failed` — подпись нашла не ту функцию.

## CHEGrenadeProjectile::Create

```
CHEGrenadeProjectile *CHEGrenadeProjectile::Create(const Vector &position, const QAngle &angles,
    const Vector &velocity, const AngularImpulse &angVelocity, CBaseCombatCharacter *pOwner, float timer)
```

Ориентиры (одинаковы во всех сборках):
- первая же операция — вызов `CBaseEntity::Create("hegrenade_projectile", position, angles, pOwner)`: ссылка на строку `hegrenade_projectile`;
- сразу после — вызов с числом `1.5` (`0x3FC00000`) — `SetDetonateTimerLength(1.5)`;
- дальше три вызова с адресом скорости: `SetAbsVelocity`, `SetupInitialTransmittedGrenadeVelocity`, `SetThrower`;
- затем сравнения и запись чисел `0.4` (`0x3ECCCCCD`, гравитация), `0.2` (`0x3E4CCCCD`, трение), `0.45` (`0x3EE66666`, упругость), `100` (`0x42C80000`, урон) и `350` (радиус = 100 × 3.5);
- в конце — `GetWeaponInfo(4)` (4 = HE).

Начало функции в версии 11003710:
- Windows 32: `55 8B EC 83 EC 0C 53 8B 5D 18 56 57 53 FF 75 0C FF 75 08 68 [адрес строки] E8 [вызов]` — `push ebp; mov ebp,esp; sub esp,0Ch; …; push [ebp+18h] (владелец); push [ebp+0Ch]; push [ebp+8]; push "hegrenade_projectile"; call CBaseEntity::Create`.
- Windows 64: `48 89 5C 24 08 48 89 6C 24 10 57 48 83 EC 40 …; 48 8D 0D [rip] E8 [вызов]` — сохранение регистров, `lea rcx, "hegrenade_projectile"`, `call CBaseEntity::Create`. Сразу за вызовом — загрузка числа 1.5 в `xmm1` и вызов `SetDetonateTimerLength`.
- Linux: `@_ZN20CHEGrenadeProjectile6CreateERK6VectorRK6QAngleS2_S2_P20CBaseCombatCharacterf`.

## CFlashbangProjectile::Create

```
CFlashbangProjectile *CFlashbangProjectile::Create(const Vector &position, const QAngle &angles,
    const Vector &velocity, const AngularImpulse &angVelocity, CBaseCombatCharacter *pOwner)
```

Ориентиры:
- первым делом `CBaseEntity::Create("flashbang_projectile", ...)`: ссылка на строку `flashbang_projectile`;
- сразу после — три вызова с адресом скорости (`SetAbsVelocity`, `SetupInitialTransmittedGrenadeVelocity`, `SetThrower`), **без** `SetDetonateTimerLength` в начале (этим она отличается от HE);
- затем число `100` (`0x42C80000`, урон) и гравитация, трение, упругость;
- рядом в бинарнике — строка `Flashbang.Explode` (звук взрыва, используется в `Detonate` флешки).

Начало в версии 11003710:
- Windows 32: `55 8B EC 51 53 8B 5D 18 56 57 53 FF 75 0C FF 75 08 68 [адрес] E8 [вызов] 8B 75 10` — после вызова `mov esi, [ebp+10h]` (скорость). У дыма начало то же, но после вызова идёт `D9 EE` (`fldz`).
- Windows 64: `48 89 5C 24 08 48 89 6C 24 10 57 48 83 EC 30 49 8B D8 49 8B E9 …; 48 8D 0D [rip] E8 [вызов]`.
- Linux: `@_ZN20CFlashbangProjectile6CreateERK6VectorRK6QAngleS2_S2_P20CBaseCombatCharacter`.

## CSmokeGrenadeProjectile::Create

```
CSmokeGrenadeProjectile *CSmokeGrenadeProjectile::Create(const Vector &position, const QAngle &angles,
    const Vector &velocity, const AngularImpulse &angVelocity, CBaseCombatCharacter *pOwner)
```

Ориентиры:
- первым делом `CBaseEntity::Create("smokegrenade_projectile", ...)`: ссылка на строку `smokegrenade_projectile`;
- сразу после — назначение функции think (адрес функции `Think_Detonate` передаётся как число) и `SetNextThink(curtime + 1.5)`: загрузка `gpGlobals->curtime` и прибавление 1.5;
- рядом в бинарнике — строки `BaseSmokeEffect.Sound` (звук срабатывания дыма) и `env_particlesmokegrenade` (облако).

Начало в версии 11003710:
- Windows 32: `55 8B EC 51 53 8B 5D 18 56 57 53 FF 75 0C FF 75 08 68 [адрес] E8 [вызов] D9 EE`.
- Windows 64: `48 89 5C 24 08 48 89 74 24 10 48 89 7C 24 18 4C 89 74 24 20 41 57 48 83 EC 30 …; 48 8D 0D [rip] E8 [вызов]`.
- Linux: `@_ZN23CSmokeGrenadeProjectile6CreateERK6VectorRK6QAngleS2_S2_P20CBaseCombatCharacter`.

## Если функцию сделать не удалось

Оставьте подпись этой сборки пустой (`""`) или удалите строку ключа. Функция будет честно выключена, остальное работает: повтор детонирует плагин. Запишите в `docs/nadepractice/PROGRESS.md`, для какой сборки и версии игры нет подписи.

---

<a name="english"></a>

# nadepractice — gamedata: what it is and how to restore it after a game update

`nadepractice` does almost everything with plain SourceMod, but one feature needs gamedata: the **real detonation of replay projectiles** (`!last`, `!show`). For it the plugin calls the game functions `CHEGrenadeProjectile::Create`, `CFlashbangProjectile::Create` and `CSmokeGrenadeProjectile::Create`, whose addresses are described in `gamedata/nadepractice.games.txt`.

After a game update the addresses may change. The plugin then **does not break**: it writes one line per function to the error log and keeps working with the fallback — detonation by the plugin (a replayed flash does not blind, an HE explosion is only an effect). This guide explains how to bring the feature back yourself, without AI assistants and possibly without internet access.

The smoke duration (menu "Smoke duration") needs no gamedata.

## How to tell gamedata is broken

- A line in the SourceMod error log (`addons/sourcemod/logs/errors_*.log`):
  `[nadepractice] Feature "real replay detonation (HE)" is disabled: gamedata is out of date (signature "CHEGrenadeProjectile::Create" not found). ... docs/nadepractice/GAMEDATA.md, section "CHEGrenadeProjectile::Create".`
- `sm_nadepractice_gamedata` in the server console: `ok` or `off: <reason>` for every function.
- The load line in the normal log: `[nadepractice] <version>, nadethrow: ..., gamedata: he ok, flash ok, smoke off`.

Reasons:
- `gamedata file ... not found` — the file was not copied to the server (see "Installation");
- `signature "..." not found` — the signature does not match: the game was updated (see the function sections);
- `the call could not be prepared` — an error in the gamedata file (a typo in a signature, a stray quote);
- `the check failed` — the signature matched the **wrong** function: the call did not return a projectile. The feature stays off until the plugin is reloaded; make the signature again.

## Installation

`gamedata/nadepractice.games.txt` → `cstrike/addons/sourcemod/gamedata/nadepractice.games.txt`. After replacing the file: `sm plugins reload nadepractice` or a map change.

## What to keep downloaded in advance

In case there is no internet when the game updates:

1. **Ghidra** (free, ghidra-sre.org; needs Java 17+, download its installer too) or **IDA Free** (hex-rays.com). Either works.
2. For Linux — `nm` and `objdump` (`binutils`); on Windows they come with Git for Windows / MSYS2 / MinGW.
3. **Copies of the server binaries from before the update** — the most important part. Before every game update save:
   - `cstrike/bin/server.dll` (Windows, 32-bit, `srcds.exe`),
   - `cstrike/bin/x64/server.dll` (Windows, 64-bit, `srcds_win64.exe`),
   - `cstrike/bin/server_srv.so` (Linux, 32-bit),
   - `cstrike/bin/linux64/server_srv.so` (Linux, 64-bit),
   - and `cstrike/steam.inf` (the `PatchVersion=` line is the game version).

   The old version is for comparison: the function is already known there (its address can be found with the current signature), and in the new version it is easier to recognise by the same landmarks.
4. This file and `gamedata/nadepractice.games.txt` of the current version.

## Four server builds

| Gamedata key | Server | File | Symbols |
|---|---|---|---|
| `windows` | Windows, 32-bit | `cstrike/bin/server.dll` | no: byte signature |
| `windows64` | Windows, 64-bit | `cstrike/bin/x64/server.dll` | no: byte signature |
| `linux` | Linux, 32-bit | `cstrike/bin/server_srv.so` | yes: `@name` |
| `linux64` | Linux, 64-bit | `cstrike/bin/linux64/server_srv.so` | yes: `@name` |

The current file was made for `PatchVersion=11003710`.

## Linux: by symbol

The Linux builds keep function names, so the gamedata has `@` and the mangled name. To check the name exists in the new binary:

```
nm server_srv.so | grep CHEGrenadeProjectile6Create
nm server_srv.so | grep CFlashbangProjectile6Create
nm server_srv.so | grep CSmokeGrenadeProjectile6Create
```

If the name changed (different parameters), copy the new one from the `nm` output (without the address and the letter `t`) and put `@` in front. Readable form: `nm -C`.

If SourceMod does not find a symbol that `nm` shows (local symbols, letter `t`), make a byte signature as for Windows.

## Windows: byte signature

A signature is the first bytes of the function with the bytes that change between builds (addresses and call offsets) replaced by `\x2A` ("any byte"). SourceMod searches `server.dll` for this sequence; it must occur **exactly once**.

### Steps

1. Open `server.dll` in Ghidra (File → Import File, then double-click and "Analyze" with default settings; analysis takes a few minutes). For 64-bit, the same with `x64/server.dll`.
2. Find the function by its landmarks (sections below). The most reliable one is the string with the projectile class name:
   Search → For Strings → filter `hegrenade_projectile` → double-click the string → the listing shows its references (XREF). There are several: one or two are the class registration (tiny functions of a couple of instructions), one is `Create` itself, one or two are other code (e.g. a class name comparison). `Create` is recognised by its start (sections below).
3. A convenient way to recognise the function is to **compare it with the Linux build of the same bitness**: open `server_srv.so` in another window (the function is named there) and compare the order of calls and constants. The order is the same, only the addresses differ.
4. Make the signature: select the first 25–50 bytes of the function (up to and including the call of `CBaseEntity::Create`) and write the bytes down. Replace with `\x2A`:
   - the 4 bytes after `E8` (call), `E9` (jmp) and `0F 8x` (conditional jump);
   - 32-bit: the 4 bytes of an absolute address (e.g. after `68` = `push string address`);
   - 64-bit: the 4 offset bytes of instructions with `[rip+...]` (e.g. `48 8D 0D xx xx xx xx` = `lea rcx, [rip+...]`).
5. Check it is unique: Search → Memory → "Hex", enter the signature with `\x2A` replaced by `.` (regular expression mode) or `??` (depends on the Ghidra version). Exactly one match must be found — the start of the function. If there are more, add bytes at the end.
   In IDA Free: Search → Sequence of bytes, `2A` replaced by `?`.
6. Put the signature into `gamedata/nadepractice.games.txt` under the right key (`windows` or `windows64`) as `"\x55\x8B\xEC..."`.

### Checking the result

1. Copy the file to the server, `sm plugins reload nadepractice`.
2. `sm_nadepractice_gamedata` — `ok` for the function.
3. The "Stage 14.2" checklist items: `!last` with a flash blinds, an HE explodes, the smoke is real. If the call returns something other than a projectile, the feature turns itself off with `the check failed` — the signature matched the wrong function.

## CHEGrenadeProjectile::Create

```
CHEGrenadeProjectile *CHEGrenadeProjectile::Create(const Vector &position, const QAngle &angles,
    const Vector &velocity, const AngularImpulse &angVelocity, CBaseCombatCharacter *pOwner, float timer)
```

Landmarks (the same in every build):
- the very first operation calls `CBaseEntity::Create("hegrenade_projectile", position, angles, pOwner)`: a reference to the string `hegrenade_projectile`;
- right after it, a call with the number `1.5` (`0x3FC00000`) — `SetDetonateTimerLength(1.5)`;
- then three calls with the velocity address: `SetAbsVelocity`, `SetupInitialTransmittedGrenadeVelocity`, `SetThrower`;
- then comparisons and stores of `0.4` (`0x3ECCCCCD`, gravity), `0.2` (`0x3E4CCCCD`, friction), `0.45` (`0x3EE66666`, elasticity), `100` (`0x42C80000`, damage) and `350` (radius = 100 × 3.5);
- at the end, `GetWeaponInfo(4)` (4 = HE).

Function start in version 11003710:
- Windows 32: `55 8B EC 83 EC 0C 53 8B 5D 18 56 57 53 FF 75 0C FF 75 08 68 [string address] E8 [call]` — `push ebp; mov ebp,esp; sub esp,0Ch; …; push [ebp+18h] (owner); push [ebp+0Ch]; push [ebp+8]; push "hegrenade_projectile"; call CBaseEntity::Create`.
- Windows 64: `48 89 5C 24 08 48 89 6C 24 10 57 48 83 EC 40 …; 48 8D 0D [rip] E8 [call]` — register saves, `lea rcx, "hegrenade_projectile"`, `call CBaseEntity::Create`. Right after the call, 1.5 is loaded into `xmm1` and `SetDetonateTimerLength` is called.
- Linux: `@_ZN20CHEGrenadeProjectile6CreateERK6VectorRK6QAngleS2_S2_P20CBaseCombatCharacterf`.

## CFlashbangProjectile::Create

```
CFlashbangProjectile *CFlashbangProjectile::Create(const Vector &position, const QAngle &angles,
    const Vector &velocity, const AngularImpulse &angVelocity, CBaseCombatCharacter *pOwner)
```

Landmarks:
- first of all `CBaseEntity::Create("flashbang_projectile", ...)`: a reference to the string `flashbang_projectile`;
- right after it, three calls with the velocity address (`SetAbsVelocity`, `SetupInitialTransmittedGrenadeVelocity`, `SetThrower`), **without** `SetDetonateTimerLength` at the start (unlike HE);
- then the number `100` (`0x42C80000`, damage) and gravity, friction, elasticity;
- nearby in the binary, the string `Flashbang.Explode` (explosion sound, used by the flashbang `Detonate`).

Start in version 11003710:
- Windows 32: `55 8B EC 51 53 8B 5D 18 56 57 53 FF 75 0C FF 75 08 68 [address] E8 [call] 8B 75 10` — after the call, `mov esi, [ebp+10h]` (velocity). The smoke starts the same way, but `D9 EE` (`fldz`) follows the call.
- Windows 64: `48 89 5C 24 08 48 89 6C 24 10 57 48 83 EC 30 49 8B D8 49 8B E9 …; 48 8D 0D [rip] E8 [call]`.
- Linux: `@_ZN20CFlashbangProjectile6CreateERK6VectorRK6QAngleS2_S2_P20CBaseCombatCharacter`.

## CSmokeGrenadeProjectile::Create

```
CSmokeGrenadeProjectile *CSmokeGrenadeProjectile::Create(const Vector &position, const QAngle &angles,
    const Vector &velocity, const AngularImpulse &angVelocity, CBaseCombatCharacter *pOwner)
```

Landmarks:
- first of all `CBaseEntity::Create("smokegrenade_projectile", ...)`: a reference to the string `smokegrenade_projectile`;
- right after it, the think function is set (the address of `Think_Detonate` is passed as a number) and `SetNextThink(curtime + 1.5)`: `gpGlobals->curtime` is loaded and 1.5 is added;
- nearby in the binary, the strings `BaseSmokeEffect.Sound` (smoke pop sound) and `env_particlesmokegrenade` (the cloud).

Start in version 11003710:
- Windows 32: `55 8B EC 51 53 8B 5D 18 56 57 53 FF 75 0C FF 75 08 68 [address] E8 [call] D9 EE`.
- Windows 64: `48 89 5C 24 08 48 89 74 24 10 48 89 7C 24 18 4C 89 74 24 20 41 57 48 83 EC 30 …; 48 8D 0D [rip] E8 [call]`.
- Linux: `@_ZN23CSmokeGrenadeProjectile6CreateERK6VectorRK6QAngleS2_S2_P20CBaseCombatCharacter`.

## If a function cannot be found

Leave the signature of that build empty (`""`) or remove the key line. The feature is then honestly off and everything else works: the replay is detonated by the plugin. Note in `docs/nadepractice/PROGRESS.md` which build and game version has no signature.
