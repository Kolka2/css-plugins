/*
 * throws.sp — обнаружение бросков: снаряд -> владелец, снимок состояния игрока
 * в момент броска, начальные позиция и скорость снаряда.
 *
 * Снаряд создаётся внутри обработки команды игрока, поэтому в SpawnPost позиция,
 * углы, скорость и кнопки игрока — те самые, с которыми он бросил. Скорость
 * снаряду игра выставляет уже после Spawn, поэтому её читаем на следующем кадре.
 */

void Throws_OnEntityCreated(int entity, const char[] classname) {
    if (entity <= MaxClients || entity > MAX_EDICTS) {
        return;
    }
    if (NadeFromProjectileClass(classname) == NADE_NONE) {
        return;
    }
    g_bProjectileEnt[entity] = true;

    // Снаряды повтора создаёт сам плагин и сам же их обрабатывает.
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

    // CSS-VERIFY: в SpawnPost у снаряда уже выставлен m_hOwnerEntity (бросивший игрок).
    // Если нет — снимок будет сделан кадром позже по m_hThrower (в лог пишется late=1).
    int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
    if (IsHuman(owner)) {
        Throws_Snapshot(owner, nade);
        g_PendingThrowRef[owner] = ref;
    }

    RequestFrame(Throws_Frame_Init, ref);
}

// Запоминает состояние игрока как «последний бросок».
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
    g_LastThrow[client].hasProj = false;
    g_LastThrow[client].hasDetonation = false;
    g_LastThrow[client].pathCount = 0;
}

public void Throws_Frame_Init(int ref) {
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

    // CSS-VERIFY: у снарядов CS:S есть сетевое свойство m_hThrower и оно указывает на бросившего.
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
        return;     // бот или снаряд без владельца — не наш случай
    }

    bool late = (g_PendingThrowRef[owner] != ref);
    if (late) {
        Throws_Snapshot(owner, nade);
    }
    g_PendingThrowRef[owner] = 0;

    float pos[3], vel[3];
    GetEntityOrigin(entity, pos);
    bool hasVel = GetEntityVelocity(entity, vel);

    g_LastThrow[owner].projOrigin = pos;
    g_LastThrow[owner].projVelocity = vel;
    g_LastThrow[owner].hasProj = hasVel;

    LogDebug("throw #%d: %N nade=%s type=%s late=%d player=(%.1f %.1f %.1f) ang=(%.2f %.2f) plvel=(%.1f %.1f %.1f) proj=(%.1f %.1f %.1f) projvel=(%.1f %.1f %.1f)",
        g_LastThrow[owner].serial, owner, g_NadeKey[nade], g_ThrowKey[g_LastThrow[owner].throwType], late,
        g_LastThrow[owner].origin[0], g_LastThrow[owner].origin[1], g_LastThrow[owner].origin[2],
        g_LastThrow[owner].angles[0], g_LastThrow[owner].angles[1],
        g_LastThrow[owner].velocity[0], g_LastThrow[owner].velocity[1], g_LastThrow[owner].velocity[2],
        pos[0], pos[1], pos[2], vel[0], vel[1], vel[2]);

    Tracer_Track(entity, owner, nade, pos, false, g_LastThrow[owner].serial);
    if (hasVel) {
        Preview_OnThrow(owner, entity);
    }
    Practice_OnThrow(owner, nade);
}
