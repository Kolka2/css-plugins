/*
 * throws.sp - throw detection: projectile -> owner, snapshot of the player state
 * at the moment of the throw, initial projectile position and velocity.
 *
 * The projectile is created while the player's command is processed, so at SpawnPost
 * the player's position, angles, velocity and buttons are exactly those of the throw.
 * The game sets the projectile velocity after Spawn, so it is read in the next frame.
 */

void Throws_OnEntityCreated(int entity, const char[] classname) {
    if (entity <= MaxClients || entity > MAX_EDICTS) {
        return;
    }
    if (NadeFromProjectileClass(classname) == NADE_NONE) {
        return;
    }
    g_bProjectileEnt[entity] = true;

    // Replay projectiles are created and handled by the plugin itself.
    if (!g_bActive || g_bReplaySpawning) {
        return;
    }
    SDKHook(entity, SDKHook_SpawnPost, Throws_OnSpawnPost);
}

void Throws_OnEntityDestroyed(int entity) {
    if (entity > 0 && entity <= MAX_EDICTS) {
        g_bProjectileEnt[entity] = false;
        g_ReplayOwner[entity] = 0;
    }
}

public void Throws_OnSpawnPost(int entity) {
    if (!g_bActive || !IsValidEntity(entity)) {
        return;
    }
    char classname[32];
    GetEntityClassname(entity, classname, sizeof(classname));
    int nade = NadeFromProjectileClass(classname);
    if (nade == NADE_NONE) {
        return;
    }

    int ref = EntIndexToEntRef(entity);
    g_ProjSpawnTime[entity] = GetGameTime();

    // CSS-VERIFY: at SpawnPost the projectile already has m_hOwnerEntity (the thrower).
    // If not, the snapshot is taken a frame later through m_hThrower (late=1 in the log).
    int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
    if (IsHuman(owner)) {
        Throws_Snapshot(owner, nade);
        g_PendingThrowRef[owner] = ref;
    }

    RequestFrame(Throws_Frame_Init, ref);
}

// Stores the player state as the "last throw".
void Throws_Snapshot(int client, int nade) {
    float origin[3], eye[3], angles[3], velocity[3];
    GetClientAbsOrigin(client, origin);
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, angles);
    GetEntityVelocity(client, velocity);

    int flags = GetEntityFlags(client);
    float speed2d = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);

    int type;
    if (!(flags & FL_ONGROUND)) {
        type = (speed2d > RUN_SPEED) ? THROW_RUNJUMP : THROW_JUMP;
        if (Throws_IsJumpthrow(client)) {
            type = (type == THROW_RUNJUMP) ? THROW_RUNJUMPTHROW : THROW_JUMPTHROW;
        }
    } else if (flags & FL_DUCKING) {
        type = THROW_CROUCH;
    } else {
        type = (speed2d > RUN_SPEED) ? THROW_RUN : THROW_STAND;
    }

    g_LastThrow[client].valid = true;
    g_LastThrow[client].serial = ++g_ThrowSerial;
    g_LastThrow[client].nade = nade;
    g_LastThrow[client].origin = origin;
    g_LastThrow[client].eye = eye;
    g_LastThrow[client].angles = angles;
    g_LastThrow[client].velocity = velocity;
    g_LastThrow[client].buttons = GetClientButtons(client);
    g_LastThrow[client].flags = flags;
    g_LastThrow[client].throwType = type;
    g_LastThrow[client].strength = 1.0;     // nadethrow tells the real one a moment later
    g_LastThrow[client].hasProj = false;
    g_LastThrow[client].hasDetonation = false;
    g_LastThrow[client].hasAirtime = false;
    g_LastThrow[client].pathCount = 0;

    float start[3];
    g_LastThrow[client].hasStart = Throws_FindStart(client, type, start);
    g_LastThrow[client].startAuto = true;
    g_LastThrow[client].startOrigin = start;
}

// Jumpthrow: the throw buttons were released in the tick jump was pressed, or within
// sm_nadepractice_jumpthrow_ticks of it - what the "+jump; -attack" alias does. The game
// creates the projectile about 0.1 s after the release, so the release tick is looked up
// in the movement buffer, not taken at the projectile spawn. With nadethrow the right
// button throws too, so its release counts as well.
// CSS-VERIFY: the order in which nadethrow and nadepractice see the buttons. nadethrow
// replaces IN_ATTACK2 with IN_ATTACK in OnPlayerRunCmd; the buffer records the buttons in
// OnPlayerRunCmdPost, after every plugin, so it sees the final buttons either way.
bool Throws_IsJumpthrow(int client) {
    int mask = IN_ATTACK;
    if (IsNadethrowEnabled()) {
        mask |= IN_ATTACK2;
    }
    int release = Movement_FindRelease(client, mask, 0.5);
    if (release == -1) {
        LogDebug("jumpthrow: %N, release tick not found in the buffer", client);
        return false;
    }
    int maxTicks = g_cvJumpthrowTicks.IntValue;
    int distance = Movement_JumpPressNear(client, release, maxTicks);
    LogDebug("jumpthrow: %N, release %d ticks ago, jump press %s%d ticks from it (limit %d)", client, release,
        (distance == -1) ? "not within " : "", (distance == -1) ? maxTicks : distance, maxTicks);
    return distance != -1;
}

// Throw types that start with a run-up / with a jump.
bool IsRunThrow(int type) {
    return type == THROW_RUN || type == THROW_RUNJUMP || type == THROW_RUNJUMPTHROW;
}

stock bool IsJumpthrowType(int type) {
    return type == THROW_JUMPTHROW || type == THROW_RUNJUMPTHROW;
}

// Where the throw started, from the movement buffer:
//   standing / crouched  - no separate start (the start is the release point);
//   jump                 - the last tick on the ground before the takeoff;
//   running / run + jump - the last point on the ground with horizontal speed below
//                          sm_nadepractice_start_speed, no older than sm_nadepractice_start_lookback.
// Returns false if there is no separate start (or it was not found).
bool Throws_FindStart(int client, int type, float start[3]) {
    float speed = g_cvStartSpeed.FloatValue;
    float lookback = g_cvStartLookback.FloatValue;
    int back = -1;
    switch (type) {
        case THROW_JUMP, THROW_JUMPTHROW: {
            back = Movement_LastOnGround(client, 0);
        }
        case THROW_RUN: {
            back = Movement_FindRunStart(client, 0, speed, lookback);
        }
        case THROW_RUNJUMP, THROW_RUNJUMPTHROW: {
            int takeoff = Movement_LastOnGround(client, 0);
            if (takeoff != -1) {
                back = Movement_FindRunStart(client, takeoff, speed, lookback);
            }
        }
        default: {
            return false;
        }
    }
    float entry[MV_SIZE];
    if (back == -1 || !Movement_Get(client, back, entry)) {
        LogDebug("start: %N, %s throw, start not found (buffer %d ticks)", client, g_ThrowKey[type], g_MoveCount[client]);
        return false;
    }
    Movement_Position(entry, start);
    LogDebug("start: %N, %s throw, start %d ticks (%.2f s) before, at (%.1f %.1f %.1f)", client, g_ThrowKey[type],
        back, GetGameTime() - entry[MV_TIME], start[0], start[1], start[2]);
    return true;
}

public void Throws_Frame_Init(int ref) {
    Throws_Process(ref, false);
}

// With nadethrow the projectile is final only after its notification; one frame more at most.
public void Throws_Frame_Retry(int ref) {
    Throws_Process(ref, true);
}

// nadethrow has adjusted (or left alone) a projectile: its strength and the final initial
// position and velocity. The notification comes after the adjustment, while the order of
// RequestFrame callbacks between plugins is not defined, so the values are taken here.
public void Nadethrow_OnGrenadeThrown(int client, int projectile, float strength) {
    if (!g_bActive || !IsHuman(client) || projectile <= MaxClients || projectile > MAX_EDICTS) {
        return;
    }
    // Replay projectiles have an owner too, so nadethrow sees them; they are not throws.
    // CSS-VERIFY: nadethrow does not change the velocity of replay projectiles (strength 1.00 here).
    if (g_ReplayOwner[projectile] != 0 || g_bReplaySpawning) {
        LogDebug("nadethrow: replay projectile %d ignored, strength %.2f%s", projectile, strength,
            (strength < 1.0) ? " (CHANGED by nadethrow)" : " (unchanged)");
        return;
    }
    g_NtRef[client] = EntIndexToEntRef(projectile);
    g_NtStrength[client] = strength;
    GetEntityOrigin(projectile, g_NtPos[client]);
    GetEntityVelocity(projectile, g_NtVel[client]);
    LogDebug("nadethrow: %N projectile %d strength %.2f", client, projectile, strength);
}

void Throws_Process(int ref, bool retry) {
    int entity = EntRefToEntIndex(ref);
    if (!g_bActive || entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity)) {
        return;
    }
    char classname[32];
    GetEntityClassname(entity, classname, sizeof(classname));
    int nade = NadeFromProjectileClass(classname);
    if (nade == NADE_NONE) {
        return;
    }

    // CSS-VERIFY: CS:S projectiles have the m_hThrower netprop and it points to the thrower.
    int owner = -1;
    if (HasEntProp(entity, Prop_Send, "m_hThrower")) {
        owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
    } else {
        LogMissingProp("m_hThrower");
    }
    if (!IsHuman(owner)) {
        owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
    }
    if (!IsHuman(owner)) {
        return;     // a bot or a projectile without an owner: not ours
    }

    // nadethrow: its notification carries the strength and the adjusted projectile.
    bool fromNadethrow = (g_NtRef[owner] == ref);
    if (!fromNadethrow && !retry && IsNadethrowEnabled()) {
        RequestFrame(Throws_Frame_Retry, ref);
        return;
    }

    bool late = (g_PendingThrowRef[owner] != ref);
    if (late) {
        Throws_Snapshot(owner, nade);
    }
    g_PendingThrowRef[owner] = 0;

    float pos[3], vel[3];
    bool hasVel;
    float strength = 1.0;
    if (fromNadethrow) {
        pos = g_NtPos[owner];
        vel = g_NtVel[owner];
        strength = g_NtStrength[owner];
        hasVel = true;
        g_NtRef[owner] = 0;
    } else {
        GetEntityOrigin(entity, pos);
        hasVel = GetEntityVelocity(entity, vel);
        if (retry) {
            LogDebug("throw: %N, no nadethrow notification for projectile %d, strength taken as 1.0", owner, entity);
        }
    }

    g_LastThrow[owner].projOrigin = pos;
    g_LastThrow[owner].projVelocity = vel;
    g_LastThrow[owner].hasProj = hasVel;
    g_LastThrow[owner].strength = strength;

    LogDebug("throw #%d: %N nade=%s type=%s strength=%.2f late=%d player=(%.1f %.1f %.1f) ang=(%.2f %.2f) plvel=(%.1f %.1f %.1f) proj=(%.1f %.1f %.1f) projvel=(%.1f %.1f %.1f) start=%s(%.1f %.1f %.1f)",
        g_LastThrow[owner].serial, owner, g_NadeKey[nade], g_ThrowKey[g_LastThrow[owner].throwType], strength, late,
        g_LastThrow[owner].origin[0], g_LastThrow[owner].origin[1], g_LastThrow[owner].origin[2],
        g_LastThrow[owner].angles[0], g_LastThrow[owner].angles[1],
        g_LastThrow[owner].velocity[0], g_LastThrow[owner].velocity[1], g_LastThrow[owner].velocity[2],
        pos[0], pos[1], pos[2], vel[0], vel[1], vel[2],
        g_LastThrow[owner].hasStart ? "" : "none", g_LastThrow[owner].startOrigin[0], g_LastThrow[owner].startOrigin[1],
        g_LastThrow[owner].startOrigin[2]);

    Tracer_Track(entity, owner, nade, pos, false, g_LastThrow[owner].serial, g_ProjSpawnTime[entity]);
    if (hasVel) {
        Preview_OnThrow(owner, entity);
    }
    Practice_OnThrow(owner, nade);
    // Last: the snapshot above must stay at the throw position.
    Measure_OnThrow(owner, nade);
}
