/*
 * tracer.sp - tracer of real throws: projectile positions every tick, bounce and
 * detonation marks, trajectories drawn for their owner only.
 *
 * Temp beams live for a limited time, so saved trajectories are redrawn in cycles.
 * To stay within the per-frame temp entity limit, a cycle is spread over time:
 * one pass sends no more than the budget (TE_Take), the rest goes in later passes.
 */

#define TRACER_DRAW_TICK 0.1    // drawing pass step, seconds

void Tracer_Init() {
    RegConsoleCmd("sm_clear", Command_Clear, "Clear your trajectories");
    RegConsoleCmd("sm_tracer", Command_Tracer, "Show throw trajectories (toggle)");

    // CSS-VERIFY: the *_detonate events exist in CS:S and carry userid, x, y, z.
    char events[NADE_COUNT][] = { "hegrenade_detonate", "flashbang_detonate", "smokegrenade_detonate" };
    for (int i = 0; i < NADE_COUNT; i++) {
        if (!HookEventEx(events[i], Event_Detonate, EventHookMode_Post)) {
            LogError("[nadepractice] Event %s not found: detonation point falls back to the last tracked position", events[i]);
        }
    }
}

void Tracer_ResetClient(int client) {
    Tracer_ClearClient(client);
    g_bTracer[client] = true;
    g_TrajNext[client] = 0;
    g_NextDraw[client] = 0.0;
}

// Clears the player's trajectories. Beams already sent live out their time (a couple of seconds).
void Tracer_ClearClient(int client) {
    for (int slot = 0; slot < MAX_TRAJ; slot++) {
        delete g_TrajPoints[client][slot];
        g_TrajSerial[client][slot] = 0;
    }
    g_DrawSlot[client] = -1;
    g_DrawIdx[client] = 0;
    g_DrawNextCycle[client] = 0.0;
}

// ---------------------------------------------------------------------------
// Trajectory storage
// ---------------------------------------------------------------------------

// Takes the next slot of the player's trajectory ring. Returns the slot.
int Tracer_NewTrajectory(int client, int nade) {
    int count = g_cvTraceCount.IntValue;
    if (count > MAX_TRAJ) {
        count = MAX_TRAJ;
    }
    // The cvar was lowered: free the extra slots.
    for (int i = count; i < MAX_TRAJ; i++) {
        delete g_TrajPoints[client][i];
    }

    int slot = g_TrajNext[client] % count;
    g_TrajNext[client] = (slot + 1) % count;

    delete g_TrajPoints[client][slot];
    g_TrajPoints[client][slot] = new ArrayList(4);
    g_TrajNade[client][slot] = nade;
    g_TrajSerial[client][slot] = ++g_TrajSerialCounter;
    return slot;
}

// Adds a point; live = draw the segment from the previous point at once.
bool Tracer_AddPoint(int client, int slot, int serial, const float pos[3], int kind, bool live) {
    ArrayList points = g_TrajPoints[client][slot];
    if (points == null || g_TrajSerial[client][slot] != serial || points.Length >= MAX_TRAJ_POINTS) {
        return false;
    }

    float point[4];
    point[0] = pos[0];
    point[1] = pos[1];
    point[2] = pos[2];
    point[3] = float(kind);
    int index = points.PushArray(point);

    if (live && g_bTracer[client] && index > 0) {
        float prev[4], a[3];
        points.GetArray(index - 1, prev);
        a[0] = prev[0];
        a[1] = prev[1];
        a[2] = prev[2];
        float life = g_cvTraceRedraw.FloatValue + 0.5;
        Draw_Beam(client, a, pos, life, g_cvTraceWidth.FloatValue, g_NadeColor[g_TrajNade[client][slot]]);
        Tracer_DrawMark(client, pos, kind, g_TrajNade[client][slot], life);
    }
    return true;
}

int Tracer_PointKind(ArrayList points, int index) {
    return RoundToNearest(view_as<float>(points.Get(index, 3)));
}

// Next point to draw/export: stride ahead, but never skipping bounces and the detonation.
int Tracer_NextPoint(ArrayList points, int index, int stride) {
    int last = points.Length - 1;
    int next = index + stride;
    if (next > last) {
        next = last;
    }
    for (int i = index + 1; i < next; i++) {
        if (Tracer_PointKind(points, i) != PT_NORMAL) {
            return i;
        }
    }
    return next;
}

int Tracer_Stride(int pointCount, int maxSegments) {
    if (maxSegments < 1) {
        maxSegments = 1;
    }
    int stride = RoundToCeil(float(pointCount - 1) / float(maxSegments));
    return (stride < 1) ? 1 : stride;
}

// Simplified trajectory for a lineup. Returns the number of points.
int Tracer_ExportPath(ArrayList points, float[] out, int maxPoints) {
    int n = points.Length;
    if (n < 1) {
        return 0;
    }
    int stride = Tracer_Stride(n, maxPoints - 1);
    int count = 0;
    int index = 0;
    float point[4];
    while (count < maxPoints) {
        points.GetArray(index, point);
        out[count * 3] = point[0];
        out[count * 3 + 1] = point[1];
        out[count * 3 + 2] = point[2];
        count++;
        if (index >= n - 1) {
            break;
        }
        // The last place always goes to the final point.
        index = (count == maxPoints - 1) ? n - 1 : Tracer_NextPoint(points, index, stride);
    }
    return count;
}

// A ready trajectory (from a lineup or the last throw) for the "draw only" replay.
void Tracer_AddStaticPath(int client, int nade, const float[] path, int count) {
    int slot = Tracer_NewTrajectory(client, nade);
    int serial = g_TrajSerial[client][slot];
    float pos[3];
    for (int i = 0; i < count; i++) {
        pos[0] = path[i * 3];
        pos[1] = path[i * 3 + 1];
        pos[2] = path[i * 3 + 2];
        Tracer_AddPoint(client, slot, serial, pos, (i == count - 1) ? PT_DETONATE : PT_NORMAL, false);
    }
    // Redraw at once, without waiting for the current cycle to end.
    g_DrawSlot[client] = -1;
    g_DrawNextCycle[client] = 0.0;
}

// ---------------------------------------------------------------------------
// Projectile tracking
// ---------------------------------------------------------------------------

void Tracer_Track(int entity, int client, int nade, const float pos[3], bool replay, int throwSerial) {
    float now = GetGameTime();

    Tracked item;
    item.ref = EntIndexToEntRef(entity);
    item.userid = GetClientUserId(client);
    item.nade = nade;
    item.replay = replay;
    item.throwSerial = throwSerial;
    item.spawnTime = now;
    item.nextSample = now + g_cvTraceSample.FloatValue;
    item.lastPos = pos;
    item.lastPoint = pos;
    item.hasVel = false;
    item.hasPrediction = false;
    item.slot = Tracer_NewTrajectory(client, nade);
    item.serial = g_TrajSerial[client][item.slot];

    Tracer_AddPoint(client, item.slot, item.serial, pos, PT_NORMAL, false);
    g_Tracked.PushArray(item);
}

int Tracer_FindByRef(int ref) {
    Tracked item;
    for (int i = 0; i < g_Tracked.Length; i++) {
        g_Tracked.GetArray(i, item);
        if (item.ref == ref) {
            return i;
        }
    }
    return -1;
}

// Attaches the predicted landing point to a tracked projectile (for the prediction check).
void Tracer_SetPrediction(int entity, const float predicted[3]) {
    int index = Tracer_FindByRef(EntIndexToEntRef(entity));
    if (index == -1) {
        return;
    }
    Tracked item;
    g_Tracked.GetArray(index, item);
    item.predicted = predicted;
    item.hasPrediction = true;
    g_Tracked.SetArray(index, item);
}

void Tracer_Frame(float now) {
    float dt = GetTickInterval();
    float gravityStep = g_cvGravity.FloatValue * g_cvSimGravity.FloatValue * dt;
    float bounceDv = g_cvTraceBounceDv.FloatValue;
    float maxTime = g_cvTraceMaxTime.FloatValue;

    Tracked item;
    for (int i = g_Tracked.Length - 1; i >= 0; i--) {
        g_Tracked.GetArray(i, item);
        int entity = EntRefToEntIndex(item.ref);
        if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity)) {
            Tracer_Finish(i, item.lastPos, false);
            continue;
        }

        float pos[3], vel[3];
        GetEntityOrigin(entity, pos);
        bool hasVel = GetEntityVelocity(entity, vel);

        if (now - item.spawnTime > maxTime) {
            // Lives too long (e.g. the smoke did not pop): close the record.
            Tracer_Finish(i, pos, false);
            continue;
        }

        // Bounce = the velocity changed within a tick more than gravity alone could.
        bool bounce = false;
        if (hasVel && item.hasVel) {
            float dv[3];
            dv[0] = vel[0] - item.lastVel[0];
            dv[1] = vel[1] - item.lastVel[1];
            dv[2] = vel[2] - item.lastVel[2] + gravityStep;
            bounce = GetVectorLength(dv) > bounceDv;
        }

        bool moved = GetVectorDistance(pos, item.lastPoint) > 1.0;
        if (bounce && moved) {
            Tracer_AddPointTracked(item, pos, PT_BOUNCE);
            item.nextSample = now + g_cvTraceSample.FloatValue;
        } else if (now >= item.nextSample) {
            if (moved) {
                Tracer_AddPointTracked(item, pos, PT_NORMAL);
            }
            item.nextSample = now + g_cvTraceSample.FloatValue;
        }

        item.lastPos = pos;
        item.lastVel = vel;
        item.hasVel = hasVel;
        g_Tracked.SetArray(i, item);
    }
}

void Tracer_AddPointTracked(Tracked item, const float pos[3], int kind) {
    int client = GetClientOfUserId(item.userid);
    if (client != 0) {
        Tracer_AddPoint(client, item.slot, item.serial, pos, kind, true);
    }
    item.lastPoint = pos;
}

// Closes a projectile record: final point, last throw data, prediction check.
void Tracer_Finish(int index, const float pos[3], bool detonated) {
    Tracked item;
    g_Tracked.GetArray(index, item);
    g_Tracked.Erase(index);

    int client = GetClientOfUserId(item.userid);
    if (client == 0 || !IsClientInGame(client)) {
        return;
    }

    Tracer_AddPoint(client, item.slot, item.serial, pos, PT_DETONATE, true);

    if (item.throwSerial != 0 && g_LastThrow[client].valid && g_LastThrow[client].serial == item.throwSerial) {
        g_LastThrow[client].detonation = pos;
        g_LastThrow[client].hasDetonation = true;
        ArrayList points = g_TrajPoints[client][item.slot];
        if (points != null && g_TrajSerial[client][item.slot] == item.serial) {
            float path[MAX_PATH_POINTS * 3];
            g_LastThrow[client].pathCount = Tracer_ExportPath(points, path, MAX_PATH_POINTS);
            g_LastThrow[client].path = path;
        }
    }

    LogDebug("trajectory end: %N nade=%s replay=%d detonated=%d at (%.1f %.1f %.1f) flight=%.2fs",
        client, g_NadeKey[item.nade], item.replay, detonated, pos[0], pos[1], pos[2], GetGameTime() - item.spawnTime);

    // A smoke whose record ended without a detonation does not count in the statistics.
    if (item.hasPrediction && (detonated || item.nade != NADE_SMOKE)) {
        Preview_OnLanded(client, item.nade, item.predicted, pos);
    }
}

void Tracer_OnEntityDestroyed(int entity) {
    if (entity <= MaxClients || entity > MAX_EDICTS || !g_bProjectileEnt[entity]) {
        return;
    }
    int index = Tracer_FindByRef(EntIndexToEntRef(entity));
    if (index != -1) {
        Tracked item;
        g_Tracked.GetArray(index, item);
        Tracer_Finish(index, item.lastPos, false);
    }
}

void Tracer_OnReplayDetonated(int entity, const float pos[3]) {
    int index = Tracer_FindByRef(EntIndexToEntRef(entity));
    if (index != -1) {
        Tracer_Finish(index, pos, true);
    }
}

public void Event_Detonate(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    int nade = (name[0] == 'h') ? NADE_HE : ((name[0] == 'f') ? NADE_FLASH : NADE_SMOKE);
    int userid = event.GetInt("userid");

    float pos[3];
    pos[0] = event.GetFloat("x");
    pos[1] = event.GetFloat("y");
    pos[2] = event.GetFloat("z");
    bool hasPos = (pos[0] != 0.0 || pos[1] != 0.0 || pos[2] != 0.0);

    // The event does not name the entity: take this player's projectile of this type closest to the point.
    int best = -1;
    float bestDist = -1.0;
    Tracked item;
    for (int i = 0; i < g_Tracked.Length; i++) {
        g_Tracked.GetArray(i, item);
        if (item.replay || item.userid != userid || item.nade != nade) {
            continue;
        }
        float dist = hasPos ? GetVectorDistance(pos, item.lastPos) : item.spawnTime;
        if (best == -1 || dist < bestDist) {
            best = i;
            bestDist = dist;
        }
    }
    if (best == -1) {
        return;
    }
    if (!hasPos) {
        g_Tracked.GetArray(best, item);
        pos = item.lastPos;
        LogDebug("%s: no coordinates in the event, using the last tracked position", name);
    }
    Tracer_Finish(best, pos, true);
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

void Tracer_DrawMark(int client, const float pos[3], int kind, int nade, float life) {
    if (kind == PT_BOUNCE) {
        Draw_Ring(client, pos, 10.0, life, 1.0, { 255, 255, 255, 255 });
    } else if (kind == PT_DETONATE) {
        Draw_Ring(client, pos, 40.0, life, 2.0, g_NadeColor[nade]);
    }
}

int Tracer_CountSegments(int client, int maxSeg) {
    int total = 0;
    for (int slot = 0; slot < MAX_TRAJ; slot++) {
        ArrayList points = g_TrajPoints[client][slot];
        if (points == null || points.Length < 2) {
            continue;
        }
        int stride = Tracer_Stride(points.Length, maxSeg);
        int index = 0;
        int guard = 0;
        while (index < points.Length - 1 && guard++ < MAX_TRAJ_POINTS) {
            index = Tracer_NextPoint(points, index, stride);
            total += (Tracer_PointKind(points, index) == PT_NORMAL) ? 1 : 2;
        }
    }
    return total;
}

void Tracer_DrawClient(int client, float now) {
    if (now < g_NextDraw[client]) {
        return;
    }
    g_NextDraw[client] = now + TRACER_DRAW_TICK;
    if (!g_bTracer[client]) {
        return;
    }

    int maxSeg = g_cvTraceMaxSeg.IntValue;

    if (g_DrawSlot[client] < 0) {
        if (now < g_DrawNextCycle[client]) {
            return;
        }
        int total = Tracer_CountSegments(client, maxSeg);
        if (total == 0) {
            g_DrawNextCycle[client] = now + 0.5;
            return;
        }
        // A cycle is no shorter than the cvar and than the time the budget needs for all segments.
        float need = float(total) / float(g_cvTeBudget.IntValue) * TRACER_DRAW_TICK + 0.2;
        float period = g_cvTraceRedraw.FloatValue;
        if (period < need) {
            period = need;
        }
        g_DrawLife[client] = period + 0.3;
        if (g_DrawLife[client] > 25.0) {
            g_DrawLife[client] = 25.0;  // temp beam lifetime limit
        }
        g_DrawNextCycle[client] = now + period;
        g_DrawSlot[client] = 0;
        g_DrawIdx[client] = 0;
    }

    float width = g_cvTraceWidth.FloatValue;
    float life = g_DrawLife[client];
    float a[4], b[4], start[3], end[3];
    int guard = 0;

    while (g_DrawSlot[client] < MAX_TRAJ && guard++ < MAX_TRAJ * MAX_TRAJ_POINTS) {
        int slot = g_DrawSlot[client];
        ArrayList points = g_TrajPoints[client][slot];
        if (points == null || g_DrawIdx[client] >= points.Length - 1) {
            g_DrawSlot[client]++;
            g_DrawIdx[client] = 0;
            continue;
        }

        int next = Tracer_NextPoint(points, g_DrawIdx[client], Tracer_Stride(points.Length, maxSeg));
        points.GetArray(g_DrawIdx[client], a);
        points.GetArray(next, b);
        start[0] = a[0];
        start[1] = a[1];
        start[2] = a[2];
        end[0] = b[0];
        end[1] = b[1];
        end[2] = b[2];

        if (!Draw_Beam(client, start, end, life, width, g_NadeColor[g_TrajNade[client][slot]])) {
            return;     // frame budget used up: continue in the next pass
        }
        Tracer_DrawMark(client, end, RoundToNearest(b[3]), g_TrajNade[client][slot], life);
        g_DrawIdx[client] = next;
    }

    g_DrawSlot[client] = -1;    // cycle finished
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

public Action Command_Clear(int client, int args) {
    if (IsHuman(client)) {
        Tracer_ClearClient(client);
        NP_Print(client, "%t", "Traces Cleared");
    }
    return Plugin_Handled;
}

public Action Command_Tracer(int client, int args) {
    if (IsHuman(client)) {
        g_bTracer[client] = !g_bTracer[client];
        Practice_TellOption(client, "Menu Tracer", g_bTracer[client]);
    }
    return Plugin_Handled;
}
