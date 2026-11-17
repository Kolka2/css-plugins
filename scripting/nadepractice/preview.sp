/*
 * preview.sp - grenade flight model, trajectory preview before the throw and
 * comparison of the prediction with the real throw.
 *
 * The CS:S grenade sources are not in the public Source SDK 2013 (HL2/HL2MP only),
 * so the model is rebuilt from the shared engine code (PhysicsToss for
 * MOVETYPE_FLYGRAVITY) and the known CS grenade logic: all constants are cvars
 * sm_nadepractice_sim_* tuned with the prediction check (!preverror, debug log).
 *
 * CSS-VERIFY: the whole model - initial velocity formula, gravity, bounce,
 * stop threshold, detonation time. Criterion: average !preverror error.
 */

#define SIM_SAMPLE_STEPS 3      // a trajectory point every this many model steps

void Preview_Init() {
    RegConsoleCmd("sm_preview", Command_Preview, "Trajectory preview before the throw (toggle)");
    RegConsoleCmd("sm_preverror", Command_PrevError, "Preview error statistics for the session (\"reset\" to start over)");
}

void Preview_ResetClient(int client) {
    g_bPreview[client] = g_cvPrevDefault.BoolValue;
    g_NextPreview[client] = 0.0;
    Preview_ResetStats(client);
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

public bool Sim_TraceFilter(int entity, int contentsMask) {
    if (entity == 0) {
        return true;        // world
    }
    if (entity <= MaxClients) {
        return false;       // the model ignores players
    }
    return !(entity <= MAX_EDICTS && g_bProjectileEnt[entity]);
}

// Throw pitch from the view pitch, as the game computes it. The view pitch is taken in 0..360
// (SourceMod gives "up" as negative): looking down (< 90) maps 0..90 to offset..offset+90*down,
// looking up maps 360..270 to offset..offset-90*up. With the defaults (-10, 100/90, 80/90) the
// throw goes 10 degrees above the view at the horizon and straight up / down at the extremes.
// Checked against 210 throws of the owner's debug log: velocity error below 0.25 units/s.
float Sim_ThrowPitch(float viewPitch) {
    float p = viewPitch;
    if (p < 0.0) {
        p += 360.0;
    }
    float offset = g_cvSimPitchOffset.FloatValue;
    if (p < 90.0) {
        return offset + p * g_cvSimThrowDownScale.FloatValue;
    }
    return offset - (360.0 - p) * g_cvSimThrowUpScale.FloatValue;
}

// Initial projectile position and velocity from the player state:
//   speed = min((90 - throwPitch) * factor, max)
//   vel   = dir(throwPitch, yaw) * speed + player velocity
//   start = eye + dir * forward (closer if a wall is in the way)
void Sim_ThrowParams(const float eye[3], const float angles[3], const float playerVel[3], float pos[3], float vel[3]) {
    float pitch = Sim_ThrowPitch(angles[0]);

    float speed = (90.0 - pitch) * g_cvSimThrowFactor.FloatValue;
    float speedMax = g_cvSimThrowMax.FloatValue;
    if (speed > speedMax) {
        speed = speedMax;
    }

    float throwAngles[3], forwardDir[3];
    throwAngles[0] = pitch;
    throwAngles[1] = angles[1];
    throwAngles[2] = 0.0;
    GetAngleVectors(throwAngles, forwardDir, NULL_VECTOR, NULL_VECTOR);

    // The projectile appears a bit in front of the eyes; at the wall if one is there
    // (the game traces a 4x4x4 box with the player's solid mask).
    float target[3], mins[3], maxs[3];
    float dist = g_cvSimForward.FloatValue;
    for (int i = 0; i < 3; i++) {
        target[i] = eye[i] + forwardDir[i] * dist;
        mins[i] = -2.0;
        maxs[i] = 2.0;
    }
    TR_TraceHullFilter(eye, target, mins, maxs, MASK_PLAYERSOLID, Sim_TraceFilter);
    TR_GetEndPosition(pos);

    float factor = g_cvSimPlayerVel.FloatValue;
    for (int i = 0; i < 3; i++) {
        vel[i] = forwardDir[i] * speed + playerVel[i] * factor;
    }
}

void Sim_AddPoint(ArrayList path, const float pos[3], int kind) {
    if (path == null || path.Length >= MAX_TRAJ_POINTS) {
        return;
    }
    float point[4];
    point[0] = pos[0];
    point[1] = pos[1];
    point[2] = pos[2];
    point[3] = float(kind);
    path.PushArray(point);
}

// Simulates the flight. path (may be null) receives trajectory points, end the detonation point.
void Sim_Run(const float startPos[3], const float startVel[3], int nade, ArrayList path, float end[3]) {
    float dt = GetTickInterval() * float(g_cvSimTickMult.IntValue);
    float gravity = g_cvGravity.FloatValue * g_cvSimGravity.FloatValue;
    float elasticity = g_cvSimElasticity.FloatValue;
    float stopSqr = g_cvSimStopSpeed.FloatValue * g_cvSimStopSpeed.FloatValue;
    int maxSteps = g_cvSimMaxSteps.IntValue;
    int maxBounces = g_cvSimMaxBounces.IntValue;
    float hull = g_cvSimHull.FloatValue;

    // HE and flash detonate at the first timer check after the fuse; smoke when it stops.
    float fuse = g_cvSimFuse.FloatValue;
    float think = g_cvSimThink.FloatValue;
    float detonateAt = fuse;
    if (think > 0.0) {
        detonateAt = float(RoundToFloor(fuse / think) + 1) * think;
    }

    float mins[3], maxs[3];
    for (int i = 0; i < 3; i++) {
        mins[i] = -hull;
        maxs[i] = hull;
    }

    float pos[3], vel[3], move[3], target[3], normal[3], lastMark[3];
    CopyVector(startPos, pos);
    CopyVector(startVel, vel);
    CopyVector(startPos, lastMark);
    Sim_AddPoint(path, pos, PT_NORMAL);

    float time = 0.0;
    int bounces = 0;
    bool resting = false;

    for (int step = 0; step < maxSteps; step++) {
        if (resting) {
            break;      // the position does not change any more
        }
        if (nade != NADE_SMOKE && time >= detonateAt) {
            break;
        }

        // Gravity as in PhysicsAddGravityMove: average vertical velocity over the step.
        float newZ = vel[2] - gravity * dt;
        move[0] = vel[0] * dt;
        move[1] = vel[1] * dt;
        move[2] = (vel[2] + newZ) * 0.5 * dt;
        vel[2] = newZ;

        AddVectors(pos, move, target);
        TR_TraceHullFilter(pos, target, mins, maxs, MASK_SOLID, Sim_TraceFilter);
        float fraction = TR_GetFraction();
        if (TR_AllSolid()) {
            resting = true;
            break;
        }
        TR_GetEndPosition(pos);

        if (fraction < 1.0) {
            TR_GetPlaneNormal(INVALID_HANDLE, normal);
            bounces++;

            // Reflection (overbounce 2.0) and speed loss.
            float backoff = GetVectorDotProduct(vel, normal) * 2.0;
            for (int i = 0; i < 3; i++) {
                vel[i] = (vel[i] - normal[i] * backoff) * elasticity;
                if (vel[i] > -0.1 && vel[i] < 0.1) {
                    vel[i] = 0.0;
                }
            }
            float speedSqr = GetVectorDotProduct(vel, vel);

            if (normal[2] > 0.7) {
                // Floor: stop, or move for the rest of the step.
                if (speedSqr < stopSqr) {
                    resting = true;
                } else {
                    float rest = (1.0 - fraction) * dt;
                    for (int i = 0; i < 3; i++) {
                        target[i] = pos[i] + vel[i] * rest;
                    }
                    TR_TraceHullFilter(pos, target, mins, maxs, MASK_SOLID, Sim_TraceFilter);
                    if (!TR_AllSolid()) {
                        TR_GetEndPosition(pos);
                    }
                }
            } else if (speedSqr < stopSqr) {
                // Wall: too slow, the velocity is dropped and the grenade falls under gravity.
                vel[0] = 0.0;
                vel[1] = 0.0;
                vel[2] = 0.0;
            }

            if (GetVectorDistance(pos, lastMark) > 2.0) {
                Sim_AddPoint(path, pos, PT_BOUNCE);
                CopyVector(pos, lastMark);
            }
            if (bounces >= maxBounces) {
                break;      // load limit
            }
        } else if ((step % SIM_SAMPLE_STEPS) == SIM_SAMPLE_STEPS - 1) {
            Sim_AddPoint(path, pos, PT_NORMAL);
            CopyVector(pos, lastMark);
        }

        time += dt;
    }

    CopyVector(pos, end);
    Sim_AddPoint(path, pos, PT_DETONATE);
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

void Preview_Frame(int client, float now) {
    if (!g_bPreview[client] || now < g_NextPreview[client]) {
        return;
    }
    float interval = g_cvPrevInterval.FloatValue;
    g_NextPreview[client] = now + interval;

    if (!IsPlayerAlive(client)) {
        return;
    }
    int nade = GetActiveNade(client);
    if (nade == NADE_NONE) {
        return;
    }

    float eye[3], angles[3], playerVel[3], pos[3], vel[3], end[3];
    GetClientEyePosition(client, eye);
    GetClientEyeAngles(client, angles);
    GetEntityVelocity(client, playerVel);
    Sim_ThrowParams(eye, angles, playerVel, pos, vel);

    g_SimPath.Clear();
    Sim_Run(pos, vel, nade, g_SimPath, end);

    // Beams live a bit longer than the interval so the line does not blink.
    // CSS-VERIFY: with a lifetime of about 0.15 s the preview line looks continuous.
    float life = interval + 0.05;
    int count = g_SimPath.Length;
    int stride = Tracer_Stride(count, g_cvPrevMaxSeg.IntValue);
    float a[4], b[4], start[3], finish[3];
    int index = 0;
    int guard = 0;
    while (index < count - 1 && guard++ < MAX_TRAJ_POINTS) {
        int next = Tracer_NextPoint(g_SimPath, index, stride);
        g_SimPath.GetArray(index, a);
        g_SimPath.GetArray(next, b);
        for (int i = 0; i < 3; i++) {
            start[i] = a[i];
            finish[i] = b[i];
        }
        if (!Draw_Beam(client, start, finish, life, 1.0, g_NadeColor[nade])) {
            break;
        }
        index = next;
    }
    Draw_Ring(client, end, 30.0, life, 1.5, g_NadeColor[nade]);
}

// ---------------------------------------------------------------------------
// Prediction check
// ---------------------------------------------------------------------------

// A real throw: compute where the model expects the detonation and attach it to the projectile.
void Preview_OnThrow(int client, int entity) {
    float eye[3], angles[3], playerVel[3], pos[3], vel[3], end[3];
    eye = g_LastThrow[client].eye;
    angles = g_LastThrow[client].angles;
    playerVel = g_LastThrow[client].velocity;

    Sim_ThrowParams(eye, angles, playerVel, pos, vel);
    Sim_Run(pos, vel, g_LastThrow[client].nade, null, end);
    Tracer_SetPrediction(entity, end);

    // The initial condition mismatch is the first thing to look at when tuning the model.
    float realPos[3], realVel[3];
    realPos = g_LastThrow[client].projOrigin;
    realVel = g_LastThrow[client].projVelocity;
    LogDebug("predict #%d: view pitch %.2f -> throw pitch %.2f | start model=(%.1f %.1f %.1f) real=(%.1f %.1f %.1f) d=%.1f | vel model=(%.1f %.1f %.1f) real=(%.1f %.1f %.1f) d=%.1f | landing model=(%.1f %.1f %.1f)",
        g_LastThrow[client].serial, angles[0], Sim_ThrowPitch(angles[0]),
        pos[0], pos[1], pos[2], realPos[0], realPos[1], realPos[2], GetVectorDistance(pos, realPos),
        vel[0], vel[1], vel[2], realVel[0], realVel[1], realVel[2], GetVectorDistance(vel, realVel),
        end[0], end[1], end[2]);
}

// The projectile detonated: compare with the prediction.
void Preview_OnLanded(int client, int nade, const float predicted[3], const float actual[3]) {
    float error = GetVectorDistance(predicted, actual);
    g_ErrCount[client]++;
    g_ErrSum[client] += error;
    g_ErrLast[client] = error;
    if (error > g_ErrMax[client]) {
        g_ErrMax[client] = error;
    }

    LogDebug("prediction error: %N nade=%s error=%.1f (dz %.1f) predicted=(%.1f %.1f %.1f) actual=(%.1f %.1f %.1f) | session: %d throws, average %.1f",
        client, g_NadeKey[nade], error, actual[2] - predicted[2], predicted[0], predicted[1], predicted[2], actual[0], actual[1], actual[2],
        g_ErrCount[client], g_ErrSum[client] / float(g_ErrCount[client]));

    // Called from OnGameFrame (tracer): check the phrase first.
    if (g_bPreview[client] && PhraseExists("Prediction Error")) {
        NP_Print(client, "%t", "Prediction Error", error);
    }
}

void Preview_TellStats(int client) {
    if (g_ErrCount[client] == 0) {
        NP_Print(client, "%t", "Prediction No Data");
        return;
    }
    NP_Print(client, "%t", "Prediction Stats", g_ErrCount[client],
        g_ErrSum[client] / float(g_ErrCount[client]), g_ErrMax[client], g_ErrLast[client]);
}

public Action Command_Preview(int client, int args) {
    if (IsHuman(client)) {
        g_bPreview[client] = !g_bPreview[client];
        Practice_TellOption(client, "Menu Preview", g_bPreview[client]);
    }
    return Plugin_Handled;
}

// !preverror - statistics; !preverror reset - start over (to compare before and after changing cvars).
public Action Command_PrevError(int client, int args) {
    if (!IsHuman(client)) {
        return Plugin_Handled;
    }
    char arg[16];
    if (args >= 1) {
        GetCmdArg(1, arg, sizeof(arg));
    }
    if (StrEqual(arg, "reset", false)) {
        Preview_ResetStats(client);
        LogDebug("prediction stats reset by %N", client);
        NP_Print(client, "%t", "Prediction Reset");
        return Plugin_Handled;
    }
    Preview_TellStats(client);
    return Plugin_Handled;
}

void Preview_ResetStats(int client) {
    g_ErrCount[client] = 0;
    g_ErrSum[client] = 0.0;
    g_ErrMax[client] = 0.0;
    g_ErrLast[client] = 0.0;
}
