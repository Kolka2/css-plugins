/*
 * smoke.sp - smoke duration of each thrower (stage 14.1), for their real smokes and their
 * replays. Chosen in the menu (!practice -> Smoke duration), limited by
 * sm_nadepractice_smoke_time_min / _max. Everyone sees a smoke, so this is a property of the
 * smoke of a given thrower.
 *
 * Without gamedata: when an env_particlesmokegrenade of a player's smoke appears, its fade
 * times (relative to its spawn: the game uses 15 and 20 s) are rewritten one frame later and
 * the cloud is removed by a timer. A smoke that must live longer than the game keeps it
 * (the projectile removes its cloud on its own schedule) gets a new cloud of the plugin.
 * CSS-VERIFY: the client follows fade times changed after the cloud appeared, and the
 * replacement cloud shows no visible jump.
 */

int g_SmokeChoices[] = { 0, 5, 10, 30, 60 };    // seconds, 0 = game default

int g_SmokeTime[MAXPLAYERS + 1];                // seconds, 0 = game default

void Smoke_ResetClient(int client) {
    g_SmokeTime[client] = 0;
}

// Duration within the limits; 0 stays 0 (game default).
int Smoke_Clamp(int seconds) {
    if (seconds <= 0) {
        return 0;
    }
    int lo = g_cvSmokeTimeMin.IntValue;
    int hi = g_cvSmokeTimeMax.IntValue;
    if (seconds < lo) {
        return lo;
    }
    return (seconds > hi) ? hi : seconds;
}

// Next menu choice, skipping values outside the limits.
void Smoke_Cycle(int client) {
    int count = sizeof(g_SmokeChoices);
    int current = 0;
    for (int i = 0; i < count; i++) {
        if (g_SmokeChoices[i] == g_SmokeTime[client]) {
            current = i;
        }
    }
    for (int step = 1; step <= count; step++) {
        int value = g_SmokeChoices[(current + step) % count];
        if (value == 0 || Smoke_Clamp(value) == value) {
            g_SmokeTime[client] = value;
            break;
        }
    }
    LogDebug("smoke: %N duration %d s", client, g_SmokeTime[client]);
}

// Lifetime of a plugin-made replay smoke: the player's choice, or sm_nadepractice_replay_smoke_time.
float Smoke_ReplayLife(int client) {
    if (client != 0 && g_SmokeTime[client] > 0) {
        return float(Smoke_Clamp(g_SmokeTime[client]));
    }
    return g_cvReplaySmokeTime.FloatValue;
}

void Smoke_MenuText(int client, char[] text, int maxlen) {
    char name[64];
    Menu_Text(client, "Menu Smoke Time", name, sizeof(name));
    if (g_SmokeTime[client] == 0) {
        char value[48];
        Menu_Text(client, "Smoke Time Default", value, sizeof(value));
        FormatEx(text, maxlen, "%s: %s", name, value);
    } else {
        FormatEx(text, maxlen, "%s: %d s", name, Smoke_Clamp(g_SmokeTime[client]));
    }
}

void Smoke_OnEntityCreated(int entity, const char[] classname) {
    if (!g_bActive || g_bOwnSmokeSpawning || !StrEqual(classname, "env_particlesmokegrenade")) {
        return;
    }
    RequestFrame(Frame_SmokeCloud, EntIndexToEntRef(entity));
}

// A cloud of a real smoke appeared: find its thrower and apply their duration.
public void Frame_SmokeCloud(int ref) {
    int cloud = EntRefToEntIndex(ref);
    if (!g_bActive || cloud == INVALID_ENT_REFERENCE || !IsValidEntity(cloud)) {
        return;
    }
    if (!HasEntProp(cloud, Prop_Send, "m_FadeStartTime") || !HasEntProp(cloud, Prop_Send, "m_FadeEndTime")) {
        LogMissingProp("env_particlesmokegrenade.m_FadeStartTime/m_FadeEndTime");
        return;
    }
    float pos[3];
    GetEntityOrigin(cloud, pos);
    float fadeStart = GetEntPropFloat(cloud, Prop_Send, "m_FadeStartTime");
    float fadeEnd = GetEntPropFloat(cloud, Prop_Send, "m_FadeEndTime");

    // The thrower: the smoke projectile closest to the cloud (it stays for a while after popping).
    int owner = 0;
    float best = 128.0;
    int projectile = -1;
    float spot[3];
    while ((projectile = FindEntityByClassname(projectile, "smokegrenade_projectile")) != -1) {
        GetEntityOrigin(projectile, spot);
        float dist = GetVectorDistance(pos, spot);
        if (dist < best && HasEntProp(projectile, Prop_Send, "m_hThrower")) {
            int thrower = GetEntPropEnt(projectile, Prop_Send, "m_hThrower");
            if (IsHuman(thrower)) {
                best = dist;
                owner = thrower;
            }
        }
    }
    LogDebug("smoke: cloud %d at (%.1f %.1f %.1f), game fade %.1f..%.1f s, thrower %d", cloud, pos[0], pos[1], pos[2],
        fadeStart, fadeEnd, owner);
    if (owner == 0 || g_SmokeTime[owner] <= 0) {
        return;
    }

    float life = float(Smoke_Clamp(g_SmokeTime[owner]));
    if (life <= fadeEnd) {
        // Shorter than the game's: fade out earlier and remove the cloud ourselves.
        float fadeLen = fadeEnd - fadeStart;
        if (fadeLen > life * 0.5) {
            fadeLen = life * 0.5;
        }
        SetEntPropFloat(cloud, Prop_Send, "m_FadeStartTime", life - fadeLen);
        SetEntPropFloat(cloud, Prop_Send, "m_FadeEndTime", life);
        g_ReplayEffects.Push(ref);
        CreateTimer(life + 0.5, Timer_KillSmoke, ref, TIMER_FLAG_NO_MAPCHANGE);
        LogDebug("smoke: %N cloud %d fades %.1f..%.1f s", owner, cloud, life - fadeLen, life);
    } else {
        // Longer than the game keeps the cloud: replace it with a cloud of the plugin.
        AcceptEntityInput(cloud, "Kill");
        Replay_SpawnSmoke(pos, life);
        LogDebug("smoke: %N cloud %d replaced by a plugin cloud of %.1f s", owner, cloud, life);
    }
}
