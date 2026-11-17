/*
 * util.sp — общее вспомогательное: лог, временные квары, проверки клиентов,
 * сообщения, отрисовка временными сущностями с бюджетом на кадр.
 */

// ---------------------------------------------------------------------------
// Лог и квары
// ---------------------------------------------------------------------------

void LogDebug(const char[] format, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);
    LogToFileEx(g_DebugLogPath, "%s", buffer);
}

// Меняет квар, запомнив исходное значение (только при первом изменении).
void SetCvarTemporarily(const char[] name, const char[] value) {
    ConVar cvar = FindConVar(name);
    if (cvar == null) {
        LogDebug("cvar %s not found, skipped", name);
        return;
    }

    char original[256];
    if (!g_SavedCvars.GetString(name, original, sizeof(original))) {
        cvar.GetString(original, sizeof(original));
        g_SavedCvars.SetString(name, original);
    }
    cvar.SetString(value);
    LogDebug("cvar %s: \"%s\" -> \"%s\"", name, original, value);
}

// Возвращает все квары, изменённые через SetCvarTemporarily.
void RestoreCvars() {
    StringMapSnapshot snapshot = g_SavedCvars.Snapshot();
    char name[128], value[256];
    for (int i = 0; i < snapshot.Length; i++) {
        snapshot.GetKey(i, name, sizeof(name));
        g_SavedCvars.GetString(name, value, sizeof(value));
        ConVar cvar = FindConVar(name);
        if (cvar != null) {
            cvar.SetString(value);
            LogDebug("cvar %s restored to \"%s\"", name, value);
        }
    }
    delete snapshot;
    g_SavedCvars.Clear();
}

// Одна запись в лог об отсутствующем свойстве движка, без падения.
void LogMissingProp(const char[] what) {
    if (!g_bLoggedMissingProp) {
        g_bLoggedMissingProp = true;
        LogError("[nadepractice] Engine property not found: %s (further misses are logged to the debug log only)", what);
    }
    LogDebug("missing prop: %s", what);
}

// ---------------------------------------------------------------------------
// Клиенты
// ---------------------------------------------------------------------------

// «Человек»: чат, меню, тренировка. Боты и SourceTV — нет.
bool IsHuman(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

// «Участник»: человек или бот в игровой команде. В этом режиме боты не участвуют
// (bot_quota 0), функция оставлена по правилу ARCHITECTURE.md (раздел 7, «Боты»).
stock bool IsParticipant(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) >= CS_TEAM_T;
}

// Человек, который сейчас может тренироваться: режим активен, игрок жив.
bool CanPractice(int client, bool tell = true) {
    if (!IsHuman(client)) {
        return false;
    }
    if (!g_bActive) {
        if (tell) {
            NP_Print(client, "%t", "Mode Inactive");
        }
        return false;
    }
    if (!IsPlayerAlive(client)) {
        if (tell) {
            NP_Print(client, "%t", "Must Be Alive");
        }
        return false;
    }
    return true;
}

void NP_Print(int client, const char[] format, any ...) {
    if (!IsHuman(client)) {
        return;
    }
    char buffer[240];
    SetGlobalTransTarget(client);
    VFormat(buffer, sizeof(buffer), format, 3);
    PrintToChat(client, "\x04[NadePractice]\x01 %s", buffer);
}

// Переведённые названия типа гранаты и типа броска для подстановки в другие фразы.
void NadeName(int client, int nade, char[] buffer, int maxlen) {
    FormatEx(buffer, maxlen, "%T", g_NadePhrase[nade], client);
}

void ThrowName(int client, int type, char[] buffer, int maxlen) {
    FormatEx(buffer, maxlen, "%T", g_ThrowPhrase[type], client);
}

// ---------------------------------------------------------------------------
// Гранаты
// ---------------------------------------------------------------------------

int NadeFromWeaponClass(const char[] classname) {
    for (int i = 0; i < NADE_COUNT; i++) {
        if (StrEqual(classname, g_NadeWeapon[i])) {
            return i;
        }
    }
    return NADE_NONE;
}

int NadeFromProjectileClass(const char[] classname) {
    for (int i = 0; i < NADE_COUNT; i++) {
        if (StrEqual(classname, g_NadeProjectile[i])) {
            return i;
        }
    }
    return NADE_NONE;
}

int NadeFromKey(const char[] key) {
    for (int i = 0; i < NADE_COUNT; i++) {
        if (StrEqual(key, g_NadeKey[i], false)) {
            return i;
        }
    }
    return NADE_NONE;
}

// Граната, которую игрок держит в руках, или NADE_NONE.
stock int GetActiveNade(int client) {
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon)) {
        return NADE_NONE;
    }
    char classname[32];
    GetEntityClassname(weapon, classname, sizeof(classname));
    return NadeFromWeaponClass(classname);
}

// Есть ли у игрока оружие данного класса. Возвращает индекс сущности или -1.
int FindWeaponByClass(int client, const char[] classname) {
    int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    char buffer[32];
    for (int i = 0; i < size; i++) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (weapon <= MaxClients || !IsValidEntity(weapon)) {
            continue;
        }
        GetEntityClassname(weapon, buffer, sizeof(buffer));
        if (StrEqual(buffer, classname)) {
            return weapon;
        }
    }
    return -1;
}

// ---------------------------------------------------------------------------
// Векторы и углы
// ---------------------------------------------------------------------------

void CopyVector(const float src[3], float dst[3]) {
    dst[0] = src[0];
    dst[1] = src[1];
    dst[2] = src[2];
}

// Приводит разницу углов к диапазону [-180, 180].
stock float NormalizeAngle(float angle) {
    while (angle > 180.0) {
        angle -= 360.0;
    }
    while (angle < -180.0) {
        angle += 360.0;
    }
    return angle;
}

void GetEntityOrigin(int entity, float origin[3]) {
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
}

// Скорость сущности. false, если у движка нет нужного свойства.
bool GetEntityVelocity(int entity, float velocity[3]) {
    if (!HasEntProp(entity, Prop_Data, "m_vecAbsVelocity")) {
        LogMissingProp("m_vecAbsVelocity");
        velocity[0] = 0.0;
        velocity[1] = 0.0;
        velocity[2] = 0.0;
        return false;
    }
    GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", velocity);
    return true;
}

// ---------------------------------------------------------------------------
// Отрисовка. Всё отправляется одному игроку и проходит через бюджет на кадр:
// движок отбрасывает временные сущности сверх лимита (sv_multiplayer_maxtempentities, 32).
// ---------------------------------------------------------------------------

bool TE_Take(int client) {
    int tick = GetGameTickCount();
    if (g_TeTick[client] != tick) {
        g_TeTick[client] = tick;
        g_TeLeft[client] = g_cvTeBudget.IntValue;
    }
    if (g_TeLeft[client] <= 0) {
        return false;
    }
    g_TeLeft[client]--;
    return true;
}

stock bool Draw_Beam(int client, const float start[3], const float end[3], float life, float width, const int color[4]) {
    if (!TE_Take(client)) {
        return false;
    }
    TE_SetupBeamPoints(start, end, g_BeamSprite, g_HaloSprite, 0, 0, life, width, width, 0, 0.0, color, 0);
    TE_SendToClient(client);
    return true;
}

// Горизонтальное кольцо. diameter — как его понимает движок (CSS-VERIFY: радиус или диаметр).
stock bool Draw_Ring(int client, const float center[3], float diameter, float life, float width, const int color[4]) {
    if (!TE_Take(client)) {
        return false;
    }
    TE_SetupBeamRingPoint(center, diameter, diameter + 1.0, g_BeamSprite, g_HaloSprite, 0, 0, life, width, 0.0, color, 0, 0);
    TE_SendToClient(client);
    return true;
}

stock bool Draw_Glow(int client, const float pos[3], float life, float size, int brightness) {
    if (!TE_Take(client)) {
        return false;
    }
    TE_SetupGlowSprite(pos, g_GlowSprite, life, size, brightness);
    TE_SendToClient(client);
    return true;
}
