/*
 * replay.sp - throw replay: creates a projectile with the saved initial position
 * and velocity; the engine computes the flight and the bounces.
 *
 * What the plugin cannot do without gamedata: trigger the projectile's own
 * detonation. The game sets the detonation timer in its Create() function, which
 * does not run for an entity made with CreateEntityByName. Therefore:
 *   - HE and flashbang are "detonated" by the plugin when the fuse runs out:
 *     explosion effect / sound for the owner only, no damage and no blindness;
 *   - the smoke is spawned by the plugin (env_particlesmokegrenade) once the projectile stops;
 *   - with sm_nadepractice_replay_engine_fuse 1 the plugin tries to start the engine
 *     think of HE/flash through m_nNextThinkTick (experimental).
 */

#define REPLAY_FLASH_SOUND "weapons/flashbang/flashbang_explode1.wav"
#define REPLAY_SMOKE_SOUND "weapons/smokegrenade/sg_explode.wav"
#define REPLAY_MAX_LIFE    12.0     // a replay projectile lives no longer than this, seconds

// Real replay (stage 14.2): the projectile is made by the game's own Create(), which sets the
// detonation timer, so the engine detonates it: a flash blinds everyone nearby (!noflash
// still works), an HE explodes (damage is blocked by the mode), the smoke is real.
// Returns false if the gamedata feature is off or the call failed.
bool Replay_ThrowReal(int client, int nade, const float pos[3], const float vel[3]) {
    if (!Gamedata_RealReplay(nade)) {
        return false;
    }
    g_bReplaySpawning = true;
    int entity = Gamedata_CreateProjectile(nade, client, pos, vel);
    g_bReplaySpawning = false;
    if (entity == -1) {
        return false;
    }
    g_ReplayOwner[entity] = GetClientUserId(client);
    SDKHook(entity, SDKHook_SetTransmit, Replay_OnTransmit);

    ReplayEnt item;
    item.ref = EntIndexToEntRef(entity);
    item.userid = GetClientUserId(client);
    item.nade = nade;
    item.real = true;       // the engine detonates it; kept only to be removed when the mode stops
    g_ReplayEnts.PushArray(item);

    float now = GetGameTime();
    Tracer_Track(entity, client, nade, pos, true, 0, now);
    Tracer_SetEngineDetonation(entity);
    LogDebug("replay: %N nade=%s ent=%d real Create() pos=(%.1f %.1f %.1f) vel=(%.1f %.1f %.1f)",
        client, g_NadeKey[nade], entity, pos[0], pos[1], pos[2], vel[0], vel[1], vel[2]);
    return true;
}

// Throws a replay projectile. Returns false on failure (the reason is in the debug log).
bool Replay_Throw(int client, int nade, const float pos[3], const float vel[3]) {
    if (Replay_ThrowReal(client, nade, pos, vel)) {
        return true;
    }
    g_bReplaySpawning = true;
    int entity = CreateEntityByName(g_NadeProjectile[nade]);
    if (entity == -1) {
        g_bReplaySpawning = false;
        LogDebug("replay: CreateEntityByName(%s) failed", g_NadeProjectile[nade]);
        return false;
    }

    SetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity", client);
    DispatchSpawn(entity);
    g_bReplaySpawning = false;

    // CSS-VERIFY: a projectile created by the plugin flies and bounces like a thrown one
    // (Spawn sets the move type; gravity, elasticity and friction are set here, as the game's Create() does).
    if (HasEntProp(entity, Prop_Send, "m_hThrower")) {
        SetEntPropEnt(entity, Prop_Send, "m_hThrower", client);
    }
    if (HasEntProp(entity, Prop_Send, "m_iTeamNum")) {
        SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
    }
    SetEntityGravity(entity, g_cvSimGravity.FloatValue);
    if (HasEntProp(entity, Prop_Data, "m_flElasticity")) {
        SetEntPropFloat(entity, Prop_Data, "m_flElasticity", g_cvSimElasticity.FloatValue);
    } else {
        LogMissingProp("m_flElasticity");
    }
    if (HasEntProp(entity, Prop_Data, "m_flFriction")) {
        SetEntPropFloat(entity, Prop_Data, "m_flFriction", g_cvSimFriction.FloatValue);
    }

    TeleportEntity(entity, pos, NULL_VECTOR, vel);

    float now = GetGameTime();
    float fuse = (nade == NADE_SMOKE) ? g_cvSimSmokeFuse.FloatValue : g_cvSimFuse.FloatValue;
    bool engineFuse = (nade != NADE_SMOKE) && g_cvReplayEngineFuse.BoolValue;

    // CSS-VERIFY: m_nNextThinkTick. -1 = the engine think never runs (the plugin detonates);
    // a future tick = the engine should detonate by itself (only if Spawn set a think function).
    if (HasEntProp(entity, Prop_Data, "m_nNextThinkTick")) {
        int tick = -1;
        if (engineFuse) {
            tick = GetGameTickCount() + RoundToCeil(fuse / GetTickInterval());
        }
        SetEntProp(entity, Prop_Data, "m_nNextThinkTick", tick);
    } else {
        LogMissingProp("m_nNextThinkTick");
        engineFuse = false;
    }

    g_ReplayOwner[entity] = GetClientUserId(client);
    SDKHook(entity, SDKHook_SetTransmit, Replay_OnTransmit);

    ReplayEnt item;
    item.ref = EntIndexToEntRef(entity);
    item.userid = GetClientUserId(client);
    item.nade = nade;
    // With the engine timer the plugin is a fallback: it detonates if the engine has not within a second.
    item.detonateAt = now + fuse + (engineFuse ? 1.0 : 0.0);
    item.nextCheck = item.detonateAt;
    item.killAt = now + REPLAY_MAX_LIFE;
    g_ReplayEnts.PushArray(item);

    Tracer_Track(entity, client, nade, pos, true, 0, now);

    LogDebug("replay: %N nade=%s ent=%d pos=(%.1f %.1f %.1f) vel=(%.1f %.1f %.1f) engineFuse=%d",
        client, g_NadeKey[nade], entity, pos[0], pos[1], pos[2], vel[0], vel[1], vel[2], engineFuse);
    return true;
}

// Checks the cooldown and starts a replay; tells the player the result.
// path/pathCount: simplified trajectory for the "draw only" mode (may be empty).
bool Replay_Request(int client, int nade, const float pos[3], const float vel[3], bool hasProj, const float[] path, int pathCount) {
    float now = GetGameTime();
    if (now < g_NextReplay[client]) {
        NP_Print(client, "%t", "Replay Cooldown");
        return false;
    }
    g_NextReplay[client] = now + g_cvReplayCooldown.FloatValue;

    if (g_cvReplayMode.IntValue == 1 && hasProj && Replay_Throw(client, nade, pos, vel)) {
        Measure_OnReplay(client, nade);
        return true;
    }
    // Fallback: draw the saved trajectory.
    if (pathCount >= 2) {
        Tracer_AddStaticPath(client, nade, path, pathCount);
        NP_Print(client, "%t", "Replay Drawn");
        return true;
    }
    NP_Print(client, "%t", "Replay Failed");
    return false;
}

public Action Replay_OnTransmit(int entity, int client) {
    if (g_cvReplayVisibleAll.BoolValue || entity <= 0 || entity > MAX_EDICTS) {
        return Plugin_Continue;
    }
    return (GetClientOfUserId(g_ReplayOwner[entity]) == client) ? Plugin_Continue : Plugin_Handled;
}

void Replay_Frame(float now) {
    ReplayEnt item;
    for (int i = g_ReplayEnts.Length - 1; i >= 0; i--) {
        g_ReplayEnts.GetArray(i, item);
        int entity = EntRefToEntIndex(item.ref);
        if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity)) {
            g_ReplayEnts.Erase(i);      // detonated by the engine or the entity was removed
            continue;
        }
        if (item.real || now < item.detonateAt || now < item.nextCheck) {
            continue;
        }

        if (item.nade == NADE_SMOKE && now < item.killAt) {
            // As in the game: a smoke pops once the grenade has stopped.
            float vel[3];
            GetEntityVelocity(entity, vel);
            if (GetVectorLength(vel) > 0.1) {
                item.nextCheck = now + g_cvSimThink.FloatValue;
                g_ReplayEnts.SetArray(i, item);
                continue;
            }
        }

        Replay_Detonate(entity, item);
        g_ReplayEnts.Erase(i);
    }
}

void Replay_Detonate(int entity, ReplayEnt item) {
    float pos[3];
    GetEntityOrigin(entity, pos);
    int client = GetClientOfUserId(item.userid);
    bool toAll = g_cvReplayVisibleAll.BoolValue;

    switch (item.nade) {
        case NADE_HE: {
            // Client-side explosion effect: no damage.
            TE_SetupExplosion(pos, g_ExplosionSprite, 5.0, 1, 0, 300, 0);
            if (toAll) {
                TE_SendToAll();
            } else if (client != 0) {
                TE_SendToClient(client);
            }
        }
        case NADE_FLASH: {
            if (toAll) {
                EmitSoundToAll(REPLAY_FLASH_SOUND, SOUND_FROM_WORLD, _, _, _, _, _, _, pos);
            } else if (client != 0) {
                EmitSoundToClient(client, REPLAY_FLASH_SOUND, SOUND_FROM_WORLD, _, _, _, _, _, _, pos);
            }
        }
        case NADE_SMOKE: {
            Replay_SpawnSmoke(pos, Smoke_ReplayLife(client));
        }
    }

    Tracer_OnReplayDetonated(entity, pos);
    AcceptEntityInput(entity, "Kill");
    LogDebug("replay: detonated by plugin, nade=%s at (%.1f %.1f %.1f)", g_NadeKey[item.nade], pos[0], pos[1], pos[2]);
}

// Smoke cloud like a real grenade's, lasting "life" seconds. Visible to all players
// (see README, limitations). Also replaces the cloud of a real smoke that must live longer
// than the game keeps it (smoke.sp).
void Replay_SpawnSmoke(const float pos[3], float life) {
    g_bOwnSmokeSpawning = true;
    int smoke = CreateEntityByName("env_particlesmokegrenade");
    g_bOwnSmokeSpawning = false;
    if (smoke == -1) {
        LogDebug("replay: env_particlesmokegrenade not created");
        return;
    }
    // CSS-VERIFY: the cloud appears with m_CurrentStage = 1 and fades by m_FadeStartTime/m_FadeEndTime.
    if (!HasEntProp(smoke, Prop_Send, "m_CurrentStage") || !HasEntProp(smoke, Prop_Send, "m_FadeStartTime")
        || !HasEntProp(smoke, Prop_Send, "m_FadeEndTime")) {
        LogMissingProp("env_particlesmokegrenade.m_CurrentStage/m_FadeStartTime/m_FadeEndTime");
        AcceptEntityInput(smoke, "Kill");
        return;
    }

    float fadeStart = life - 5.0;
    if (fadeStart < 1.0) {
        fadeStart = 1.0;
    }

    TeleportEntity(smoke, pos, NULL_VECTOR, NULL_VECTOR);
    SetEntProp(smoke, Prop_Send, "m_CurrentStage", 1);
    SetEntPropFloat(smoke, Prop_Send, "m_FadeStartTime", fadeStart);
    SetEntPropFloat(smoke, Prop_Send, "m_FadeEndTime", life);
    DispatchSpawn(smoke);
    ActivateEntity(smoke);
    EmitSoundToAll(REPLAY_SMOKE_SOUND, SOUND_FROM_WORLD, _, _, _, _, _, _, pos);

    int ref = EntIndexToEntRef(smoke);
    g_ReplayEffects.Push(ref);
    CreateTimer(life + 0.5, Timer_KillSmoke, ref, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillSmoke(Handle timer, int ref) {
    Replay_KillRef(ref);
    int index = g_ReplayEffects.FindValue(ref);
    if (index != -1) {
        g_ReplayEffects.Erase(index);
    }
    return Plugin_Stop;
}

void Replay_KillRef(int ref) {
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity)) {
        AcceptEntityInput(entity, "Kill");
    }
}

// The mode stopped: remove everything the replay created.
void Replay_Stop() {
    ReplayEnt item;
    for (int i = 0; i < g_ReplayEnts.Length; i++) {
        g_ReplayEnts.GetArray(i, item);
        Replay_KillRef(item.ref);
    }
    g_ReplayEnts.Clear();

    for (int i = 0; i < g_ReplayEffects.Length; i++) {
        Replay_KillRef(g_ReplayEffects.Get(i));
    }
    g_ReplayEffects.Clear();
}
