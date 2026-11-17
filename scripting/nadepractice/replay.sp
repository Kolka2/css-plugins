/*
 * replay.sp — повтор броска: создаёт снаряд с сохранёнными начальными позицией
 * и скоростью, полёт и отскоки считает движок.
 *
 * Чего плагин без gamedata сделать не может: вызвать у снаряда штатную
 * детонацию. Игра назначает таймер детонации в своей функции Create(), которая
 * для сущности, созданной через CreateEntityByName, не выполняется. Поэтому:
 *   - HE и флешку по истечении времени «взрывает» плагин: эффект взрыва / звук
 *     только владельцу, без урона и ослепления;
 *   - дым плагин ставит сам через env_particlesmokegrenade, когда снаряд остановился;
 *   - при sm_nadepractice_replay_engine_fuse 1 для HE/флешки пробуем запустить
 *     think движка через m_nNextThinkTick (экспериментально).
 */

#define REPLAY_FLASH_SOUND "weapons/flashbang/flashbang_explode1.wav"
#define REPLAY_SMOKE_SOUND "weapons/smokegrenade/sg_explode.wav"
#define REPLAY_MAX_LIFE    12.0     // снаряд повтора живёт не дольше этого, с

// Бросает снаряд повтора. Возвращает false, если не получилось (причина — в debug-логе).
bool Replay_Throw(int client, int nade, const float pos[3], const float vel[3]) {
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

    // CSS-VERIFY: снаряд, созданный плагином, летит и отскакивает как брошенный игроком
    // (тип движения выставляет Spawn; гравитацию, упругость и трение — мы, как Create() игры).
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

    // CSS-VERIFY: m_nNextThinkTick. -1 = think движка не сработает (детонирует плагин);
    // будущий тик = движок должен сдетонировать сам (только если Spawn назначил think).
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
    // При таймере движка плагин подстраховывает: взрывает сам, если движок не справился за секунду.
    item.detonateAt = now + fuse + (engineFuse ? 1.0 : 0.0);
    item.nextCheck = item.detonateAt;
    item.killAt = now + REPLAY_MAX_LIFE;
    g_ReplayEnts.PushArray(item);

    Tracer_Track(entity, client, nade, pos, true, 0);

    LogDebug("replay: %N nade=%s ent=%d pos=(%.1f %.1f %.1f) vel=(%.1f %.1f %.1f) engineFuse=%d",
        client, g_NadeKey[nade], entity, pos[0], pos[1], pos[2], vel[0], vel[1], vel[2], engineFuse);
    return true;
}

// Проверяет кулдаун и запускает повтор; сообщает игроку о результате.
// path/pathCount — упрощённая траектория для режима «только отрисовка» (может быть пустой).
bool Replay_Request(int client, int nade, const float pos[3], const float vel[3], bool hasProj, const float[] path, int pathCount) {
    float now = GetGameTime();
    if (now < g_NextReplay[client]) {
        NP_Print(client, "%t", "Replay Cooldown");
        return false;
    }
    g_NextReplay[client] = now + g_cvReplayCooldown.FloatValue;

    if (g_cvReplayMode.IntValue == 1 && hasProj && Replay_Throw(client, nade, pos, vel)) {
        return true;
    }
    // Запасной вариант: показать сохранённую траекторию.
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
            g_ReplayEnts.Erase(i);      // сдетонировал движок или сущность удалена
            continue;
        }
        if (now < item.detonateAt || now < item.nextCheck) {
            continue;
        }

        if (item.nade == NADE_SMOKE && now < item.killAt) {
            // Как в игре: дым срабатывает, когда граната остановилась.
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
            // Клиентский эффект взрыва: урона не наносит.
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
            Replay_SpawnSmoke(pos);
        }
    }

    Tracer_OnReplayDetonated(entity, pos);
    AcceptEntityInput(entity, "Kill");
    LogDebug("replay: detonated by plugin, nade=%s at (%.1f %.1f %.1f)", g_NadeKey[item.nade], pos[0], pos[1], pos[2]);
}

// Облако дыма как у настоящей гранаты. Видно всем игрокам (см. README, ограничения).
void Replay_SpawnSmoke(const float pos[3]) {
    int smoke = CreateEntityByName("env_particlesmokegrenade");
    if (smoke == -1) {
        LogDebug("replay: env_particlesmokegrenade not created");
        return;
    }
    // CSS-VERIFY: облако появляется при m_CurrentStage = 1 и рассеивается по m_FadeStartTime/m_FadeEndTime.
    if (!HasEntProp(smoke, Prop_Send, "m_CurrentStage") || !HasEntProp(smoke, Prop_Send, "m_FadeStartTime")
        || !HasEntProp(smoke, Prop_Send, "m_FadeEndTime")) {
        LogMissingProp("env_particlesmokegrenade.m_CurrentStage/m_FadeStartTime/m_FadeEndTime");
        AcceptEntityInput(smoke, "Kill");
        return;
    }

    float life = g_cvReplaySmokeTime.FloatValue;
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

// Режим остановлен: убрать всё, что создал повтор.
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
