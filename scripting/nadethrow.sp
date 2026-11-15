/*
 * nadethrow — броски гранат разной силы: ЛКМ — сильный, ЛКМ+ПКМ — средний, ПКМ — лёгкий.
 *
 * Слой:        сервис
 * Владеет:     обработкой ПКМ, пока у игрока в руках граната;
 *              начальными скоростью и позицией снаряда для бросков с силой меньше 1.0
 * Читает:      кнопки игрока, активное оружие, скорость игрока
 * Использует:  ничего (только sdktools, sdkhooks)
 * API:         include/nadethrow.inc
 *
 * Как бросает гранату сама CS:S (weapon_basecsgrenade.cpp, по открытому коду Source SDK;
 * на сервере не проверено, см. пометки CSS-VERIFY):
 *  - ЛКМ выдёргивает чеку (m_bPinPulled), бросок начинается в тике, когда IN_ATTACK отпущена;
 *  - снаряд создаётся через 0.1 с после этого (m_fThrowTime), из ItemPostFrame, то есть
 *    внутри обработки команды игрока;
 *  - скорость снаряда = направление * сила + скорость игрока в момент создания снаряда.
 * Поэтому сила броска запоминается в тике отпускания кнопок, а скорость игрока — при
 * появлении снаряда.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <nadethrow>

#define PLUGIN_VERSION "1.0.0"

#define STRENGTH_NONE   -1.0
#define STRENGTH_FULL   1.0
#define STRENGTH_MEDIUM 0.5
#define STRENGTH_LIGHT  0.0

#define THROW_BUTTONS (IN_ATTACK | IN_ATTACK2)

// Сколько секунд после отпускания кнопок запомненная сила ждёт появления снаряда
// (игра создаёт его через 0.1 с).
#define THROW_LATCH_LIFETIME 0.5
// Как часто повторять подсказку, пока сила не меняется.
#define HINT_INTERVAL 1.0
// Половина стороны куба для проверки новой точки вылета (как в коде броска CS:S).
#define TRACE_HULL_SIZE 2.0

public Plugin myinfo = {
    name        = "[CS:S] Nade throw strength",
    author      = "Kolka2",
    description = "Left / left+right / right click grenade throws of different strength",
    version     = PLUGIN_VERSION,
    url         = ""
};

ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvMinScale;
ConVar g_cvZOffset;
ConVar g_cvHint;
ConVar g_cvBots;
ConVar g_cvReleaseGrace;

GlobalForward g_fwdOnGrenadeThrown;

char g_DebugLogPath[PLATFORM_MAX_PATH];

// --- Ввод (на игрока) ---
// Активное оружие, для которого посчитано состояние ниже.
int g_iWeaponRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
bool g_bGrenadeInHand[MAXPLAYERS + 1];
// Кнопки, по которым сейчас считается сила (0 — ни одна не зажата).
int g_iHeldMask[MAXPLAYERS + 1];
// Отпускание одной из двух кнопок, которое ещё не учтено (см. sm_nadethrow_release_grace).
int g_iPendingMask[MAXPLAYERS + 1];
float g_fPendingMaskTime[MAXPLAYERS + 1];
// Сила в момент броска: ждёт появления снаряда.
bool g_bThrowLatched[MAXPLAYERS + 1];
float g_fThrowStrength[MAXPLAYERS + 1];
float g_fThrowTime[MAXPLAYERS + 1];
// Подсказка.
int g_iHintMask[MAXPLAYERS + 1];
float g_fNextHint[MAXPLAYERS + 1];

// --- Снаряд (на игрока-владельца) ---
// Снаряд, который появился и ждёт поправки.
int g_iProjectileRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
// Последний обработанный снаряд (чтобы запасной путь через RequestFrame не обработал его снова).
int g_iDoneRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_fProjectileStrength[MAXPLAYERS + 1];
// Скорость игрока в момент появления снаряда.
float g_vecPlayerVel[MAXPLAYERS + 1][3];

// Сообщения об отсутствующих свойствах — по одному разу.
bool g_bLoggedNoPinProp;
bool g_bLoggedNoVelProp;
bool g_bLoggedNoOwnerProp;

// ---------------------------------------------------------------------------
// Загрузка
// ---------------------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (GetEngineVersion() != Engine_CSS) {
        strcopy(error, err_max, "This plugin supports Counter-Strike: Source only.");
        return APLRes_Failure;
    }

    CreateNative("Nadethrow_GetApiVersion", Native_GetApiVersion);
    CreateNative("Nadethrow_IsEnabled", Native_IsEnabled);
    CreateNative("Nadethrow_GetThrowStrength", Native_GetThrowStrength);
    CreateNative("Nadethrow_GetMinScale", Native_GetMinScale);
    CreateNative("Nadethrow_GetZOffset", Native_GetZOffset);
    RegPluginLibrary(NADETHROW_LIBRARY);
    return APLRes_Success;
}

public void OnPluginStart() {
    LoadTranslations("nadethrow.phrases");

    CreateConVar("sm_nadethrow_version", PLUGIN_VERSION, "Версия плагина", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled      = CreateConVar("sm_nadethrow_enabled", "1", "Включить броски разной силы (ЛКМ / ЛКМ+ПКМ / ПКМ)", _, true, 0.0, true, 1.0);
    g_cvDebug        = CreateConVar("sm_nadethrow_debug", "0", "Подробный лог в logs/nadethrow_debug.log", _, true, 0.0, true, 1.0);
    g_cvMinScale     = CreateConVar("sm_nadethrow_min_scale", "0.3", "Доля собственной скорости броска при силе 0.0 (ПКМ)", _, true, 0.0, true, 1.0);
    g_cvZOffset      = CreateConVar("sm_nadethrow_z_offset", "12.0", "На сколько юнитов ниже вылетает граната при силе 0.0 (ПКМ)", _, true, 0.0, true, 64.0);
    g_cvHint         = CreateConVar("sm_nadethrow_hint", "0", "Показывать силу броска, пока игрок держит гранату с выдернутой чекой", _, true, 0.0, true, 1.0);
    g_cvBots         = CreateConVar("sm_nadethrow_bots", "0", "Обрабатывать ли ботов", _, true, 0.0, true, 1.0);
    g_cvReleaseGrace = CreateConVar("sm_nadethrow_release_grace", "0.1", "Сколько секунд после отпускания одной из двух кнопок сила ещё считается по обеим (0 — сила строго по последнему тику)", _, true, 0.0, true, 0.5);
    AutoExecConfig(true, "nadethrow");

    g_cvEnabled.AddChangeHook(OnEnabledChanged);

    g_fwdOnGrenadeThrown = new GlobalForward("Nadethrow_OnGrenadeThrown", ET_Ignore, Param_Cell, Param_Cell, Param_Float);

    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/nadethrow_debug.log");

    HookEvent("player_death", Event_PlayerReset);
    HookEvent("player_spawn", Event_PlayerReset);

    // Поздняя загрузка: на игроков ничего не вешается, достаточно чистого состояния.
    ResetAll();
}

public void OnAllPluginsLoaded() {
    LogMessage("[nadethrow] %s, optional libraries: none", PLUGIN_VERSION);
}

public void OnMapStart() {
    ResetAll();
}

public void OnMapEnd() {
    ResetAll();
}

public void OnClientDisconnect(int client) {
    ResetClient(client);
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    ResetAll();
    LogDebug("enabled changed: %s -> %s", oldValue, newValue);
}

public void Event_PlayerReset(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client != 0) {
        ResetInput(client);
    }
}

void ResetAll() {
    for (int client = 1; client <= MaxClients; client++) {
        ResetClient(client);
    }
}

void ResetClient(int client) {
    ResetInput(client);
    g_iProjectileRef[client] = INVALID_ENT_REFERENCE;
    g_iDoneRef[client] = INVALID_ENT_REFERENCE;
}

// Сбрасывает всё, что относится к вводу: смена оружия, смерть, выход, смена карты.
// Снаряд, который уже вылетел и ждёт поправки, остаётся: его сила уже определена.
void ResetInput(int client) {
    g_iWeaponRef[client] = INVALID_ENT_REFERENCE;
    g_bGrenadeInHand[client] = false;
    g_iHeldMask[client] = 0;
    g_iPendingMask[client] = 0;
    g_bThrowLatched[client] = false;
    g_iHintMask[client] = 0;
    g_fNextHint[client] = 0.0;
}

// ---------------------------------------------------------------------------
// Ввод и сила броска
// ---------------------------------------------------------------------------

// Обрабатывает ли плагин ввод этого игрока. Люди — всегда, боты — по квару.
bool IsHandledClient(int client) {
    return !IsFakeClient(client) || g_cvBots.BoolValue;
}

public Action OnPlayerRunCmd(int client, int &buttons) {
    if (!g_cvEnabled.BoolValue || !IsHandledClient(client)) {
        return Plugin_Continue;
    }
    if (!IsPlayerAlive(client)) {
        if (g_iWeaponRef[client] != INVALID_ENT_REFERENCE) {
            ResetInput(client);
        }
        return Plugin_Continue;
    }

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int weaponRef = (weapon > 0) ? EntIndexToEntRef(weapon) : INVALID_ENT_REFERENCE;
    if (weaponRef != g_iWeaponRef[client]) {
        // Смена оружия отменяет и удержание, и незавершённый бросок.
        ResetInput(client);
        g_iWeaponRef[client] = weaponRef;
        g_bGrenadeInHand[client] = (weapon > 0) && IsGrenadeWeapon(weapon);
    }
    if (!g_bGrenadeInHand[client]) {
        return Plugin_Continue;
    }

    int mask = buttons & THROW_BUTTONS;
    if (mask == 0) {
        if (g_iHeldMask[client] != 0) {
            OnThrowButtonsReleased(client, weapon);
        }
        return Plugin_Continue;
    }

    UpdateHeldMask(client, mask);
    if (g_cvHint.BoolValue) {
        ShowHint(client, weapon);
    }

    // Только ЛКМ: команда не меняется вообще, обычный бросок остаётся обычным.
    if (mask == IN_ATTACK) {
        return Plugin_Continue;
    }

    // CSS-VERIFY: ПКМ с гранатой в CS:S сама по себе ничего не делает (у гранат нет SecondaryAttack).
    // CSS-VERIFY: подмена ПКМ на IN_ATTACK не ломает анимацию выдёргивания чеки (клиент не
    // предсказывает нажатие, анимация приходит с сервера — возможна задержка или рывок модели рук).
    buttons = (buttons | IN_ATTACK) & ~IN_ATTACK2;
    return Plugin_Changed;
}

// Обновляет кнопки, по которым считается сила. Добавление кнопки учитывается сразу.
// Отпускание одной из двух — только если оставшаяся удерживается дольше
// sm_nadethrow_release_grace: пальцы редко отпускают обе кнопки в одном тике, и без этого
// средний бросок превращался бы в сильный или лёгкий.
void UpdateHeldMask(int client, int mask) {
    int held = g_iHeldMask[client];
    if (mask == held) {
        g_iPendingMask[client] = 0;
        return;
    }

    bool released = (mask & ~held) == 0;  // новых кнопок нет, только отпущена одна из двух
    float grace = g_cvReleaseGrace.FloatValue;
    if (released && grace > 0.0) {
        float now = GetGameTime();
        if (g_iPendingMask[client] != mask) {
            g_iPendingMask[client] = mask;
            g_fPendingMaskTime[client] = now;
        }
        if (now - g_fPendingMaskTime[client] < grace) {
            return;
        }
    }

    g_iHeldMask[client] = mask;
    g_iPendingMask[client] = 0;
    LogDebug("%N: holding, strength %.1f", client, MaskToStrength(mask));
}

// Обе кнопки отпущены: игра в этом тике начинает бросок, если чека выдернута.
void OnThrowButtonsReleased(int client, int weapon) {
    float strength = MaskToStrength(g_iHeldMask[client]);
    g_iHeldMask[client] = 0;
    g_iPendingMask[client] = 0;
    g_iHintMask[client] = 0;

    // Кнопку могли зажать и отпустить, когда чеку выдернуть нельзя (доставание гранаты,
    // сразу после предыдущего броска) — тогда броска не будет и запоминать нечего.
    if (!IsPinPulled(weapon)) {
        LogDebug("%N: released, pin not pulled, no throw", client);
        return;
    }

    g_bThrowLatched[client] = true;
    g_fThrowStrength[client] = strength;
    g_fThrowTime[client] = GetGameTime();
    LogDebug("%N: released, throw strength %.1f", client, strength);
}

// Забирает силу для появившегося снаряда. Нет свежего броска с ПКМ — значит обычный бросок.
float ConsumeThrowStrength(int client) {
    if (!g_bThrowLatched[client]) {
        return STRENGTH_FULL;
    }
    g_bThrowLatched[client] = false;
    if (GetGameTime() - g_fThrowTime[client] > THROW_LATCH_LIFETIME) {
        return STRENGTH_FULL;
    }
    return g_fThrowStrength[client];
}

float MaskToStrength(int mask) {
    if (mask == THROW_BUTTONS) {
        return STRENGTH_MEDIUM;
    }
    if (mask == IN_ATTACK) {
        return STRENGTH_FULL;
    }
    if (mask == IN_ATTACK2) {
        return STRENGTH_LIGHT;
    }
    return STRENGTH_NONE;
}

bool IsGrenadeWeapon(int weapon) {
    char classname[32];
    if (!GetEntityClassname(weapon, classname, sizeof(classname))) {
        return false;
    }
    return StrEqual(classname, "weapon_hegrenade")
        || StrEqual(classname, "weapon_flashbang")
        || StrEqual(classname, "weapon_smokegrenade");
}

// Выдернута ли чека. Если свойства нет, считаем, что выдернута, пока кнопка зажата.
bool IsPinPulled(int weapon) {
    if (weapon <= 0 || !IsValidEntity(weapon)) {
        return false;
    }
    // CSS-VERIFY: у гранат CS:S есть сетевое свойство m_bPinPulled, и оно true с тика нажатия до тика отпускания.
    if (!HasEntProp(weapon, Prop_Send, "m_bPinPulled")) {
        if (!g_bLoggedNoPinProp) {
            g_bLoggedNoPinProp = true;
            LogError("m_bPinPulled not found on grenade weapon, assuming the pin is pulled while a button is held");
        }
        return true;
    }
    return GetEntProp(weapon, Prop_Send, "m_bPinPulled") != 0;
}

void ShowHint(int client, int weapon) {
    if (IsFakeClient(client) || !IsPinPulled(weapon)) {
        return;
    }

    int mask = g_iHeldMask[client];
    float now = GetGameTime();
    if (mask == g_iHintMask[client] && now < g_fNextHint[client]) {
        return;
    }
    g_iHintMask[client] = mask;
    g_fNextHint[client] = now + HINT_INTERVAL;

    // CSS-VERIFY: текст по центру не мешает и держится дольше HINT_INTERVAL (иначе будет мигать).
    if (mask == THROW_BUTTONS) {
        PrintCenterText(client, "%t", "Hint medium");
    } else if (mask == IN_ATTACK) {
        PrintCenterText(client, "%t", "Hint strong");
    } else {
        PrintCenterText(client, "%t", "Hint light");
    }
}

// ---------------------------------------------------------------------------
// Снаряд
// ---------------------------------------------------------------------------

public void OnEntityCreated(int entity, const char[] classname) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    if (StrEqual(classname, "hegrenade_projectile")
        || StrEqual(classname, "flashbang_projectile")
        || StrEqual(classname, "smokegrenade_projectile")) {
        SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawnPost);
    }
}

public void OnProjectileSpawnPost(int entity) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    int ref = EntIndexToEntRef(entity);

    // CSS-VERIFY: в момент SpawnPost владелец уже известен через m_hOwnerEntity (m_hThrower игра
    // выставляет позже). Если нет — владелец найдётся в следующем кадре, см. Frame_Projectile.
    int client = GetProjectileOwner(entity);
    if (client != 0) {
        RegisterProjectile(client, ref);
    }

    // Скорость снаряда игра задаёт после Spawn, поэтому поправка — позже:
    // в OnPlayerRunCmdPost владельца (тот же тик), а если не вышло — в следующем кадре.
    RequestFrame(Frame_Projectile, ref);
}

// Запоминает снаряд за владельцем: сила броска и скорость игрока на этот момент.
void RegisterProjectile(int client, int ref) {
    g_iProjectileRef[client] = ref;
    g_fProjectileStrength[client] = ConsumeThrowStrength(client);
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_vecPlayerVel[client]);
}

// Снаряд создаётся внутри обработки команды игрока, так что здесь он уже с начальной
// скоростью, но ещё не пролетел ни тика и не ушёл клиентам: поправка без рывка.
// CSS-VERIFY: поправка действительно происходит здесь (в debug-логе «via cmdpost», а не «via frame»).
public void OnPlayerRunCmdPost(int client, int buttons) {
    if (g_iProjectileRef[client] != INVALID_ENT_REFERENCE) {
        FinishProjectile(client, true);
    }
}

// Запасной путь: следующий кадр после появления снаряда.
public void Frame_Projectile(int ref) {
    int entity = EntRefToEntIndex(ref);
    if (entity == INVALID_ENT_REFERENCE) {
        return;
    }

    for (int client = 1; client <= MaxClients; client++) {
        if (g_iDoneRef[client] == ref) {
            return;
        }
        if (g_iProjectileRef[client] == ref) {
            FinishProjectile(client, false);
            return;
        }
    }

    // Владелец не был известен при появлении снаряда.
    int client = GetProjectileOwner(entity);
    if (client == 0) {
        LogDebug("projectile %d: owner not found, left unchanged", entity);
        return;
    }
    RegisterProjectile(client, ref);
    FinishProjectile(client, false);
}

void FinishProjectile(int client, bool fromCmdPost) {
    int ref = g_iProjectileRef[client];
    int entity = EntRefToEntIndex(ref);
    if (entity == INVALID_ENT_REFERENCE || !IsClientInGame(client)) {
        g_iProjectileRef[client] = INVALID_ENT_REFERENCE;
        return;
    }

    float strength = g_fProjectileStrength[client];
    if (strength < STRENGTH_FULL) {
        if (!AdjustProjectile(entity, client, strength, fromCmdPost)) {
            if (fromCmdPost) {
                // Скорость ещё не задана — попробует запасной путь в следующем кадре.
                return;
            }
            // Поправить не удалось: снаряд остался обычным, так и сообщаем.
            strength = STRENGTH_FULL;
        }
    } else {
        LogDebug("%N: projectile %d, strength 1.0, unchanged", client, entity);
    }

    g_iProjectileRef[client] = INVALID_ENT_REFERENCE;
    g_iDoneRef[client] = ref;

    Call_StartForward(g_fwdOnGrenadeThrown);
    Call_PushCell(client);
    Call_PushCell(entity);
    Call_PushFloat(strength);
    Call_Finish();
}

// Пересчитывает скорость и точку вылета снаряда. false — снаряд не изменён.
bool AdjustProjectile(int entity, int client, float strength, bool fromCmdPost) {
    if (!HasEntProp(entity, Prop_Data, "m_vecAbsVelocity")) {
        if (!g_bLoggedNoVelProp) {
            g_bLoggedNoVelProp = true;
            LogError("m_vecAbsVelocity not found on grenade projectile, throws are not adjusted");
        }
        return false;
    }

    float pos[3], vel[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
    GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);
    if (GetVectorLength(vel, true) < 1.0) {
        LogDebug("%N: projectile %d has no velocity yet (%s)", client, entity, fromCmdPost ? "cmdpost" : "frame");
        return false;
    }

    // Скорость: масштабируется только собственная часть броска, скорость игрока остаётся.
    // CSS-VERIFY: CS:S добавляет к броску скорость игрока целиком (vForward * flVel + GetAbsVelocity()),
    // взятую в момент создания снаряда. Проверка: бросок ПКМ на бегу вперёд и назад.
    float k = g_cvMinScale.FloatValue + (1.0 - g_cvMinScale.FloatValue) * strength;
    float newVel[3];
    for (int i = 0; i < 3; i++) {
        newVel[i] = (vel[i] - g_vecPlayerVel[client][i]) * k + g_vecPlayerVel[client][i];
    }

    // Позиция: ниже на (1 - strength) * zOffset, если по пути нет препятствия.
    float newPos[3];
    newPos = pos;
    float drop = (1.0 - strength) * g_cvZOffset.FloatValue;
    bool lowered = false;
    if (drop > 0.0) {
        newPos[2] -= drop;
        float mins[3] = { -TRACE_HULL_SIZE, -TRACE_HULL_SIZE, -TRACE_HULL_SIZE };
        float maxs[3] = { TRACE_HULL_SIZE, TRACE_HULL_SIZE, TRACE_HULL_SIZE };
        Handle trace = TR_TraceHullFilterEx(pos, newPos, mins, maxs, MASK_SOLID, TraceFilter_NoPlayers, entity);
        lowered = !TR_DidHit(trace) && !TR_StartSolid(trace);
        delete trace;
        if (!lowered) {
            newPos = pos;
        }
    }

    // CSS-VERIFY: игра не перезаписывает скорость снаряда после этого, и на клиенте нет рывка гранаты
    // в начале полёта (особенно если в debug-логе «via frame»).
    TeleportEntity(entity, newPos, NULL_VECTOR, newVel);

    // Клиент строит начало траектории по m_vecInitialVelocity; держим её согласованной.
    // CSS-VERIFY: свойство есть у снарядов CS:S; без него возможен рывок в первые кадры.
    if (HasEntProp(entity, Prop_Send, "m_vecInitialVelocity")) {
        SetEntPropVector(entity, Prop_Send, "m_vecInitialVelocity", newVel);
    }

    LogDebug("%N: projectile %d via %s, strength %.2f, k %.2f, player vel (%.1f %.1f %.1f), vel (%.1f %.1f %.1f) -> (%.1f %.1f %.1f), pos (%.1f %.1f %.1f) -> (%.1f %.1f %.1f)%s",
        client, entity, fromCmdPost ? "cmdpost" : "frame", strength, k,
        g_vecPlayerVel[client][0], g_vecPlayerVel[client][1], g_vecPlayerVel[client][2],
        vel[0], vel[1], vel[2], newVel[0], newVel[1], newVel[2],
        pos[0], pos[1], pos[2], newPos[0], newPos[1], newPos[2],
        (drop > 0.0 && !lowered) ? " (blocked, position kept)" : "");
    return true;
}

// Препятствием считается всё, кроме игроков и самого снаряда.
public bool TraceFilter_NoPlayers(int entity, int contentsMask, any projectile) {
    return entity > MaxClients && entity != projectile;
}

// Игрок, бросивший снаряд, или 0.
int GetProjectileOwner(int entity) {
    // CSS-VERIFY: владелец снаряда читается из m_hThrower или m_hOwnerEntity.
    bool hasThrower = HasEntProp(entity, Prop_Send, "m_hThrower");
    bool hasOwner = HasEntProp(entity, Prop_Send, "m_hOwnerEntity");
    if (!hasThrower && !hasOwner && !g_bLoggedNoOwnerProp) {
        g_bLoggedNoOwnerProp = true;
        LogError("Neither m_hThrower nor m_hOwnerEntity found on grenade projectile, throws are not adjusted");
    }

    int owner = hasThrower ? GetEntPropEnt(entity, Prop_Send, "m_hThrower") : -1;
    if (!IsValidClientIndex(owner) && hasOwner) {
        owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    }
    if (!IsValidClientIndex(owner) || !IsClientInGame(owner)) {
        return 0;
    }
    return owner;
}

bool IsValidClientIndex(int client) {
    return client >= 1 && client <= MaxClients;
}

// ---------------------------------------------------------------------------
// Нативы
// ---------------------------------------------------------------------------

public int Native_GetApiVersion(Handle plugin, int numParams) {
    return NADETHROW_API_VERSION;
}

public int Native_IsEnabled(Handle plugin, int numParams) {
    return g_cvEnabled.BoolValue;
}

public any Native_GetThrowStrength(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    if (!IsValidClientIndex(client) || !IsClientInGame(client)) {
        return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is invalid or not in game", client);
    }

    if (g_iHeldMask[client] == 0 || !IsPinPulled(EntRefToEntIndex(g_iWeaponRef[client]))) {
        return STRENGTH_NONE;
    }
    return MaskToStrength(g_iHeldMask[client]);
}

public any Native_GetMinScale(Handle plugin, int numParams) {
    return g_cvMinScale.FloatValue;
}

public any Native_GetZOffset(Handle plugin, int numParams) {
    return g_cvZOffset.FloatValue;
}

// ---------------------------------------------------------------------------
// Вспомогательное
// ---------------------------------------------------------------------------

void LogDebug(const char[] format, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);
    LogToFileEx(g_DebugLogPath, "%s", buffer);
}
