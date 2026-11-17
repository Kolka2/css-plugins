/*
 * hints.sp - hints for the selected lineup: a ring at the throw spot, an aim
 * marker, a ring at the landing spot, text with the distance and the aim
 * deviation. Everything is visible to the player only.
 */

#define HINT_DRAW_PERIOD 1.0    // how often the rings are redrawn, seconds

char g_ArrowsUnicode[8][] = { "↑", "↖", "←", "↙", "↓", "↘", "→", "↗" };
char g_ArrowsAscii[8][] = { "^", "<^", "<", "<v", "v", "v>", ">", "^>" };

void Hints_Init() {
    RegConsoleCmd("sm_hints", Command_Hints, "Hints for the selected lineup (toggle)");
    g_HudSync = CreateHudSynchronizer();
}

void Hints_ResetClient(int client) {
    g_bHints[client] = true;
    g_SelectedLineup[client] = 0;
    g_NextHint[client] = 0.0;
    g_NextHintDraw[client] = 0.0;
    g_bHintShown[client] = false;
    g_HintMarkerStyle[client] = g_cvHintMarker.IntValue;
}

public bool Hints_TraceWorld(int entity, int contentsMask) {
    return entity == 0 || entity > MaxClients;
}

// Selects a lineup for hints and precomputes the points to draw.
void Hints_Select(int client, int id) {
    int index = Lineups_IndexById(id);
    if (index == -1) {
        return;
    }
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);

    // A jump throw position is recorded in the air: the hint leads to the ground point below it.
    float origin[3], below[3], ground[3];
    origin = lineup.origin;
    below = origin;
    below[2] -= 256.0;
    TR_TraceRayFilter(origin, below, MASK_PLAYERSOLID, RayType_EndPoint, Hints_TraceWorld);
    if (TR_DidHit()) {
        TR_GetEndPosition(ground);
    } else {
        ground = origin;
    }

    // Aim marker: a point on the view ray from the eyes of a player standing at the throw spot.
    float eye[3], angles[3], forwardDir[3], target[3], marker[3];
    eye = ground;
    eye[2] += (lineup.throwType == THROW_CROUCH) ? 47.0 : 64.0;
    angles = lineup.angles;
    GetAngleVectors(angles, forwardDir, NULL_VECTOR, NULL_VECTOR);
    float dist = g_cvHintLookDist.FloatValue;
    for (int i = 0; i < 3; i++) {
        target[i] = eye[i] + forwardDir[i] * dist;
    }
    TR_TraceRayFilter(eye, target, MASK_SOLID, RayType_EndPoint, Hints_TraceWorld);
    float fraction = TR_GetFraction();
    // Stop a bit short of the wall so the sprite does not sink into it.
    float reach = dist * fraction - 8.0;
    if (reach < 16.0) {
        reach = 16.0;
    }
    for (int i = 0; i < 3; i++) {
        marker[i] = eye[i] + forwardDir[i] * reach;
    }

    g_HintGround[client] = ground;
    g_HintMarker[client] = marker;
    g_HintMarkerDist[client] = reach;
    g_SelectedLineup[client] = id;
    g_bHints[client] = true;
    g_NextHint[client] = 0.0;
    g_NextHintDraw[client] = 0.0;
}

void Hints_Deselect(int client) {
    g_SelectedLineup[client] = 0;
    Hints_ClearText(client);
}

void Hints_Toggle(int client) {
    g_bHints[client] = !g_bHints[client];
    if (!g_bHints[client]) {
        Hints_ClearText(client);
    }
}

public Action Command_Hints(int client, int args) {
    if (IsHuman(client)) {
        Hints_Toggle(client);
        Practice_TellOption(client, "Menu Hints", g_bHints[client]);
    }
    return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

void Hints_SendKeyHint(int client, const char[] text) {
    Handle msg = StartMessageOne("KeyHintText", client);
    if (msg == null) {
        return;
    }
    BfWriteByte(msg, 1);
    BfWriteString(msg, text);
    EndMessage();
}

// ready: aim and position are within tolerance (in HUD mode the text turns green).
void Hints_ShowText(int client, const char[] text, bool ready) {
    switch (g_cvHintMode.IntValue) {
        case 1: {
            PrintHintText(client, "%s", text);
        }
        case 2: {
            // CSS-VERIFY: HudMsg (ShowSyncHudText) is displayed in CS:S; if not, use modes 0 and 1.
            float hold = g_cvHintInterval.FloatValue + 0.2;
            if (ready) {
                SetHudTextParams(-1.0, 0.62, hold, 60, 255, 60, 255, 0, 0.0, 0.0, 0.0);
            } else {
                SetHudTextParams(-1.0, 0.62, hold, 255, 220, 60, 255, 0, 0.0, 0.0, 0.0);
            }
            ShowSyncHudText(client, g_HudSync, "%s", text);
        }
        default: {
            // CSS-VERIFY: KeyHintText shows multi-line text on the right without a sound.
            Hints_SendKeyHint(client, text);
        }
    }
    g_bHintShown[client] = true;
}

void Hints_ClearText(int client) {
    if (g_bHintShown[client] && IsHuman(client) && g_cvHintMode.IntValue == 0) {
        Hints_SendKeyHint(client, "");
    }
    g_bHintShown[client] = false;
    g_HintMarkerStyle[client] = g_cvHintMarker.IntValue;
}

// ---------------------------------------------------------------------------
// Aim marker
// ---------------------------------------------------------------------------

// Draws the aim marker of the selected lineup. aimOk: the crosshair is within tolerance.
//   frame  - a square whose angular size is the aim tolerance (2 x sm_nadepractice_hint_angle_tolerance),
//            so "crosshair inside the frame" = "aim within tolerance"; yellow, green when aimOk;
//   cross  - two lines of the same size and colors;
//   sprite - the old glow sprite (white, does not change color).
void Hints_DrawMarker(int client, const float lineupAngles[3], bool aimOk, float life) {
    float marker[3];
    marker = g_HintMarker[client];
    int style = g_HintMarkerStyle[client];
    if (style == MARKER_SPRITE) {
        Draw_Glow(client, marker, life, 0.3, 255);
        return;
    }

    float angles[3], fwd[3], right[3], up[3];
    angles = lineupAngles;
    angles[2] = 0.0;
    GetAngleVectors(angles, fwd, right, up);

    // The aim check compares pitch and yaw separately. A pitch change of tol degrees moves the
    // view by tol degrees, a yaw change only by about tol * cos(pitch).
    float tol = g_cvHintAngleTol.FloatValue;
    float dist = g_HintMarkerDist[client];
    float halfUp = dist * Tangent(DegToRad(tol));
    float halfRight = dist * Tangent(DegToRad(tol * Cosine(DegToRad(lineupAngles[0]))));

    int color[4] = { 255, 220, 60, 255 };
    if (aimOk) {
        color = { 60, 255, 60, 255 };
    }
    float width = g_cvHintMarkerWidth.FloatValue;
    float a[3], b[3], c[3], d[3];

    if (style == MARKER_CROSS) {
        for (int i = 0; i < 3; i++) {
            a[i] = marker[i] - right[i] * halfRight;
            b[i] = marker[i] + right[i] * halfRight;
            c[i] = marker[i] - up[i] * halfUp;
            d[i] = marker[i] + up[i] * halfUp;
        }
        Draw_Beam(client, a, b, life, width, color);
        Draw_Beam(client, c, d, life, width, color);
        return;
    }

    // Frame: corners top-left, top-right, bottom-right, bottom-left.
    for (int i = 0; i < 3; i++) {
        a[i] = marker[i] - right[i] * halfRight + up[i] * halfUp;
        b[i] = marker[i] + right[i] * halfRight + up[i] * halfUp;
        c[i] = marker[i] + right[i] * halfRight - up[i] * halfUp;
        d[i] = marker[i] - right[i] * halfRight - up[i] * halfUp;
    }
    Draw_Beam(client, a, b, life, width, color);
    Draw_Beam(client, b, c, life, width, color);
    Draw_Beam(client, c, d, life, width, color);
    Draw_Beam(client, d, a, life, width, color);
}

void Hints_CycleMarker(int client) {
    g_HintMarkerStyle[client] = (g_HintMarkerStyle[client] + 1) % MARKER_COUNT;
    g_NextHint[client] = 0.0;   // redraw at once
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

void Hints_Frame(int client, float now) {
    if (now < g_NextHint[client]) {
        return;
    }
    g_NextHint[client] = now + g_cvHintInterval.FloatValue;

    if (!g_bHints[client] || g_SelectedLineup[client] == 0) {
        return;
    }
    int index = Lineups_IndexById(g_SelectedLineup[client]);
    if (index == -1) {
        Hints_Deselect(client);
        return;
    }
    if (!IsPlayerAlive(client)) {
        return;
    }

    Lineup lineup;
    g_Lineups.GetArray(index, lineup);

    // Called several times a second: check every phrase before formatting.
    if (!PhraseExists("Hint Position") || !PhraseExists("Hint Aim") || !PhraseExists("Hint Throw")
        || !PhraseExists("Hint Ready") || !PhraseExists(g_NadePhrase[lineup.nade])
        || !PhraseExists(g_ThrowPhrase[lineup.throwType])) {
        return;
    }

    float origin[3], angles[3], ground[3];
    GetClientAbsOrigin(client, origin);
    GetClientEyeAngles(client, angles);
    ground = g_HintGround[client];

    // Position: horizontal distance and direction relative to the view.
    float dx = ground[0] - origin[0];
    float dy = ground[1] - origin[1];
    float dist = SquareRoot(dx * dx + dy * dy);
    bool posOk = dist <= g_cvHintPosRadius.FloatValue;

    // Aim: positive dPitch = aim lower, positive dYaw = turn left.
    float dPitch = lineup.angles[0] - angles[0];
    float dYaw = NormalizeAngle(lineup.angles[1] - angles[1]);
    float tol = g_cvHintAngleTol.FloatValue;
    bool pitchOk = FloatAbs(dPitch) <= tol;
    bool yawOk = FloatAbs(dYaw) <= tol;
    bool ready = posOk && pitchOk && yawOk;

    bool unicode = g_cvHintUnicode.BoolValue;
    char posLine[64], aimLine[96], throwName[48], text[320];
    FormatEx(throwName, sizeof(throwName), "%T", g_ThrowPhrase[lineup.throwType], client);

    if (posOk) {
        FormatEx(posLine, sizeof(posLine), "%T: OK", "Hint Position", client);
    } else {
        float toSpot = RadToDeg(ArcTangent2(dy, dx));
        int sector = RoundToNearest(NormalizeAngle(toSpot - angles[1]) / 45.0);
        sector = (sector + 8) % 8;
        FormatEx(posLine, sizeof(posLine), "%T: %d u %s", "Hint Position", client, RoundToNearest(dist),
            unicode ? g_ArrowsUnicode[sector] : g_ArrowsAscii[sector]);
    }

    if (pitchOk && yawOk) {
        FormatEx(aimLine, sizeof(aimLine), "%T: OK", "Hint Aim", client);
    } else {
        char yawPart[40], pitchPart[40];
        if (yawOk) {
            strcopy(yawPart, sizeof(yawPart), "OK");
        } else {
            FormatEx(yawPart, sizeof(yawPart), "%s %.1f°", (dYaw > 0.0) ? (unicode ? "←" : "<") : (unicode ? "→" : ">"), FloatAbs(dYaw));
        }
        if (pitchOk) {
            strcopy(pitchPart, sizeof(pitchPart), "OK");
        } else {
            FormatEx(pitchPart, sizeof(pitchPart), "%s %.1f°", (dPitch > 0.0) ? (unicode ? "↓" : "v") : (unicode ? "↑" : "^"), FloatAbs(dPitch));
        }
        FormatEx(aimLine, sizeof(aimLine), "%T: %s  %s", "Hint Aim", client, yawPart, pitchPart);
    }

    FormatEx(text, sizeof(text), "%s [%T]\n%T: %s\n%s\n%s", lineup.name, g_NadePhrase[lineup.nade], client,
        "Hint Throw", client, throwName, posLine, aimLine);
    if (ready) {
        Format(text, sizeof(text), "%s\n%T", text, "Hint Ready", client, throwName);
    }
    Hints_ShowText(client, text, ready);

    // The aim marker is redrawn with every text update, so its color follows the aim state
    // at once; the beams live a bit longer than the interval so the marker does not blink.
    Hints_DrawMarker(client, lineup.angles, pitchOk && yawOk, g_cvHintInterval.FloatValue + 0.15);

    // Rings are updated less often than the text: they are budgeted temp entities.
    if (now < g_NextHintDraw[client]) {
        return;
    }
    g_NextHintDraw[client] = now + HINT_DRAW_PERIOD;
    float life = HINT_DRAW_PERIOD + 0.2;

    float ring[3], landing[3];
    ring = ground;
    ring[2] += 2.0;
    // CSS-VERIFY: the ring size matches sm_nadepractice_hint_pos_radius.
    int ringColor[4] = { 255, 220, 60, 255 };
    if (ready) {
        ringColor = { 60, 255, 60, 255 };
    }
    Draw_Ring(client, ring, g_cvHintPosRadius.FloatValue * 2.0 + 8.0, life, 2.0, ringColor);

    if (lineup.hasDetonation) {
        landing = lineup.detonation;
        Draw_Ring(client, landing, 60.0, life, 2.0, g_NadeColor[lineup.nade]);
    }
}
