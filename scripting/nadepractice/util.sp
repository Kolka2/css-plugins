/*
 * util.sp - shared helpers: logging, temporary cvars, client checks,
 * chat messages, temp entity drawing with a per-frame budget.
 */

// ---------------------------------------------------------------------------
// Logging and cvars
// ---------------------------------------------------------------------------

void LogDebug(const char[] format, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);
    LogToFileEx(g_DebugLogPath, "%s", buffer);
}

// Changes a cvar and remembers its original value (on the first change only).
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

// Restores every cvar changed through SetCvarTemporarily.
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

// One log entry about a missing engine property, without failing.
void LogMissingProp(const char[] what) {
    if (!g_bLoggedMissingProp) {
        g_bLoggedMissingProp = true;
        LogError("[nadepractice] Engine property not found: %s (further misses are logged to the debug log only)", what);
    }
    LogDebug("missing prop: %s", what);
}

// ---------------------------------------------------------------------------
// Clients
// ---------------------------------------------------------------------------

// "Human": chat, menus, practice. Not bots or SourceTV.
bool IsHuman(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

// "Participant": a human or a bot in a playing team. Bots do not take part in this
// mode (bot_quota 0); the function is kept per ARCHITECTURE.md (section 7, "Bots").
stock bool IsParticipant(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) >= CS_TEAM_T;
}

// A human who can practise right now: the mode is active and the player is alive.
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
    PrintToChat(client, CHAT_PREFIX ... "%s", buffer);
}

// Whether a phrase exists. A missing phrase is logged once. Check before formatting
// in frequent handlers: a translation error there aborts the handler and floods the log.
bool PhraseExists(const char[] phrase) {
    if (TranslationPhraseExists(phrase)) {
        return true;
    }
    int dummy;
    if (!g_MissingPhrases.GetValue(phrase, dummy)) {
        g_MissingPhrases.SetValue(phrase, 1);
        LogError("[nadepractice] Phrase \"%s\" not found: install translations/nadepractice.phrases.txt (and ru/)", phrase);
    }
    return false;
}

// Translated grenade and throw type names to be inserted into other phrases.
void NadeName(int client, int nade, char[] buffer, int maxlen) {
    FormatEx(buffer, maxlen, "%T", g_NadePhrase[nade], client);
}

void ThrowName(int client, int type, char[] buffer, int maxlen) {
    FormatEx(buffer, maxlen, "%T", g_ThrowPhrase[type], client);
}

// ---------------------------------------------------------------------------
// Grenades
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

// The grenade the player holds, or NADE_NONE.
stock int GetActiveNade(int client) {
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon)) {
        return NADE_NONE;
    }
    char classname[32];
    GetEntityClassname(weapon, classname, sizeof(classname));
    return NadeFromWeaponClass(classname);
}

// Whether the player has a weapon of this class. Returns its entity index or -1.
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
// Vectors and angles
// ---------------------------------------------------------------------------

void CopyVector(const float src[3], float dst[3]) {
    dst[0] = src[0];
    dst[1] = src[1];
    dst[2] = src[2];
}

// Brings an angle difference into [-180, 180].
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

// Entity velocity. false if the engine has no such property.
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
// Drawing. Everything is sent to one player and goes through a budget per network update:
// the engine drops temp entities above its limit (sv_multiplayer_maxtempentities, 32) in one
// update packet. A client with cl_updaterate below the tick rate gets several ticks in one
// packet, so the budget covers one update interval, not one tick.
// CSS-VERIFY: with cl_updaterate 20 and 10 trajectories no segments go missing.
// ---------------------------------------------------------------------------

// Update interval of the client: 1 / cl_updaterate clamped by sv_min/maxupdaterate, at least
// one tick. Read again once a second.
float TE_UpdateInterval(int client) {
    float now = GetGameTime();
    if (now >= g_TeRateCheck[client] || g_TeInterval[client] <= 0.0) {
        g_TeRateCheck[client] = now + 1.0;
        float tick = GetTickInterval();
        float rate = 1.0 / tick;
        char buffer[16];
        if (!IsFakeClient(client) && GetClientInfo(client, "cl_updaterate", buffer, sizeof(buffer))) {
            float value = StringToFloat(buffer);
            if (value > 0.0) {
                rate = value;
            }
        }
        if (g_cvMaxUpdateRate != null && g_cvMaxUpdateRate.FloatValue > 0.0 && rate > g_cvMaxUpdateRate.FloatValue) {
            rate = g_cvMaxUpdateRate.FloatValue;
        }
        if (g_cvMinUpdateRate != null && rate < g_cvMinUpdateRate.FloatValue) {
            rate = g_cvMinUpdateRate.FloatValue;
        }
        float interval = (rate > 0.0) ? 1.0 / rate : tick;
        g_TeInterval[client] = (interval < tick) ? tick : interval;
    }
    return g_TeInterval[client];
}

// Temp entities the client can still get in the current update window.
int TE_Left(int client) {
    float now = GetGameTime();
    if (now >= g_TeWindowEnd[client]) {
        // Half a tick early, so timing jitter never merges two windows into one.
        g_TeWindowEnd[client] = now + TE_UpdateInterval(client) - GetTickInterval() * 0.5;
        g_TeLeft[client] = g_cvTeBudget.IntValue;
    }
    return g_TeLeft[client];
}

bool TE_Take(int client) {
    if (TE_Left(client) <= 0) {
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

// Horizontal ring. diameter is passed as the engine takes it (CSS-VERIFY: radius or diameter).
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
