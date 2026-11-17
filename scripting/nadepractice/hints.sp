/*
 * hints.sp - hints for the selected lineup: rings at the start and at the release
 * point with a line between them (the run-up), an aim marker, a ring at the landing
 * spot, text with the distance and the aim deviation. Everything is visible to the
 * player only.
 *
 * Two places of a lineup (stage 9): the start - where to stand before the run-up or the
 * jump - and the release point, where the grenade left the hand. The position check
 * refers to one of them (TARGET_*, chosen in the menu): auto = the start if it exists
 * and is farther than the position tolerance from the release point, otherwise the
 * release point.
 */

#define HINT_DRAW_PERIOD 1.0    // how often the rings are redrawn, seconds

char g_ArrowsUnicode[8][] = { "↑", "↖", "←", "↙", "↓", "↘", "→", "↗" };
char g_ArrowsAscii[8][] = { "^", "<^", "<", "<v", "v", "v>", ">", "^>" };

int g_ColorWait[4] = { 255, 220, 60, 255 };     // yellow: not in tolerance yet
int g_ColorOk[4] = { 60, 255, 60, 255 };        // green: in tolerance
int g_ColorSecond[4] = { 110, 200, 255, 255 };  // light blue: the other place and the run-up line

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
    g_bHintHasStart[client] = false;
    g_HintMarkerStyle[client] = g_cvHintMarker.IntValue;
    g_HintTarget[client] = g_cvHintTarget.IntValue;
}

public bool Hints_TraceWorld(int entity, int contentsMask) {
    return entity == 0 || entity > MaxClients;
}

// Ground point under a position (a jump throw is released in the air).
void Hints_GroundBelow(const float pos[3], float ground[3]) {
    float from[3], below[3];
    from = pos;
    from[2] += 2.0;
    below = pos;
    below[2] -= 256.0;
    TR_TraceRayFilter(from, below, MASK_PLAYERSOLID, RayType_EndPoint, Hints_TraceWorld);
    if (TR_DidHit()) {
        TR_GetEndPosition(ground);
    } else {
        ground = pos;
    }
}

// Aim marker: a point on the view ray from the eyes of a player standing at "ground".
// Returns the distance from the eyes to the marker.
float Hints_ComputeMarker(const float ground[3], float eyeHeight, const float lineupAngles[3], float marker[3]) {
    float eye[3], angles[3], forwardDir[3], target[3];
    eye = ground;
    eye[2] += eyeHeight;
    angles = lineupAngles;
    GetAngleVectors(angles, forwardDir, NULL_VECTOR, NULL_VECTOR);
    float dist = g_cvHintLookDist.FloatValue;
    for (int i = 0; i < 3; i++) {
        target[i] = eye[i] + forwardDir[i] * dist;
    }
    TR_TraceRayFilter(eye, target, MASK_SOLID, RayType_EndPoint, Hints_TraceWorld);
    // Stop a bit short of the wall so the marker does not sink into it.
    float reach = dist * TR_GetFraction() - 8.0;
    if (reach < 16.0) {
        reach = 16.0;
    }
    for (int i = 0; i < 3; i++) {
        marker[i] = eye[i] + forwardDir[i] * reach;
    }
    return reach;
}

// Selects a lineup for hints and precomputes the points to draw.
void Hints_Select(int client, int id) {
    int index = Lineups_IndexById(id);
    if (index == -1) {
        return;
    }
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);

    float release[3], start[3], marker[3];
    release = lineup.origin;
    Hints_GroundBelow(release, g_HintRelease[client]);
    float releaseEye = (lineup.throwType == THROW_CROUCH) ? 47.0 : 64.0;
    g_HintReleaseMarkerDist[client] = Hints_ComputeMarker(g_HintRelease[client], releaseEye, lineup.angles, marker);
    g_HintReleaseMarker[client] = marker;

    g_bHintHasStart[client] = lineup.hasStart;
    if (lineup.hasStart) {
        start = lineup.startOrigin;
        Hints_GroundBelow(start, g_HintStart[client]);
        // The player stands up at the start of a run-up or a jump.
        g_HintStartMarkerDist[client] = Hints_ComputeMarker(g_HintStart[client], 64.0, lineup.angles, marker);
        g_HintStartMarker[client] = marker;
    }

    g_SelectedLineup[client] = id;
    g_bHints[client] = true;
    g_NextHint[client] = 0.0;
    g_NextHintDraw[client] = 0.0;
}

// Recomputes the hints of everyone who selected this lineup (after an edit).
void Hints_Refresh(int id) {
    for (int client = 1; client <= MaxClients; client++) {
        if (g_SelectedLineup[client] == id && IsClientInGame(client)) {
            Hints_Select(client, id);
        }
    }
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

void Hints_CycleTarget(int client) {
    g_HintTarget[client] = (g_HintTarget[client] + 1) % TARGET_COUNT;
    g_NextHint[client] = 0.0;
    g_NextHintDraw[client] = 0.0;
}

// Whether the position check refers to the start (otherwise to the release point).
bool Hints_TargetIsStart(int client) {
    if (!g_bHintHasStart[client]) {
        return false;
    }
    switch (g_HintTarget[client]) {
        case TARGET_START: {
            return true;
        }
        case TARGET_RELEASE: {
            return false;
        }
    }
    float dx = g_HintStart[client][0] - g_HintRelease[client][0];
    float dy = g_HintStart[client][1] - g_HintRelease[client][1];
    return SquareRoot(dx * dx + dy * dy) > g_cvHintPosRadius.FloatValue;
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
            // Confirmed on the server: HudMsg (ShowSyncHudText) is displayed and turns green.
            float hold = g_cvHintInterval.FloatValue + 0.2;
            if (ready) {
                SetHudTextParams(-1.0, 0.62, hold, 60, 255, 60, 255, 0, 0.0, 0.0, 0.0);
            } else {
                SetHudTextParams(-1.0, 0.62, hold, 255, 220, 60, 255, 0, 0.0, 0.0, 0.0);
            }
            ShowSyncHudText(client, g_HudSync, "%s", text);
        }
        default: {
            // Confirmed on the server: KeyHintText shows multi-line text on the right.
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

    int color[4];
    color = g_ColorWait;
    if (aimOk) {
        color = g_ColorOk;
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
    if (!PhraseExists("Hint Start") || !PhraseExists("Hint Release") || !PhraseExists("Hint Aim")
        || !PhraseExists("Hint Throw") || !PhraseExists("Hint Ready") || !PhraseExists("Hint No Start")
        || !PhraseExists("Hint Alias") || !PhraseExists("Hint Alias Nadethrow")
        || !PhraseExists("Hint Buttons") || !PhraseExists("Hint Buttons Now") || !PhraseExists("Hint Need Nadethrow")
        || !PhraseExists(g_StrengthPhrase[STRENGTH_FULL]) || !PhraseExists(g_StrengthPhrase[STRENGTH_MEDIUM])
        || !PhraseExists(g_StrengthPhrase[STRENGTH_LIGHT])
        || !PhraseExists(g_NadePhrase[lineup.nade]) || !PhraseExists(g_ThrowPhrase[lineup.throwType])) {
        return;
    }

    bool atStart = Hints_TargetIsStart(client);
    float origin[3], angles[3], ground[3];
    GetClientAbsOrigin(client, origin);
    GetClientEyeAngles(client, angles);
    if (atStart) {
        ground = g_HintStart[client];
        g_HintMarker[client] = g_HintStartMarker[client];
        g_HintMarkerDist[client] = g_HintStartMarkerDist[client];
    } else {
        ground = g_HintRelease[client];
        g_HintMarker[client] = g_HintReleaseMarker[client];
        g_HintMarkerDist[client] = g_HintReleaseMarkerDist[client];
    }

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
    // Buttons (nadethrow): while the pin is pulled the current strength must match the lineup's.
    // Without the pin pulled only a plain left click lineup counts as matching.
    int needGroup = StrengthGroup(lineup.strength);
    float current = GetCurrentStrength(client);
    bool buttonsOk = (current >= 0.0) ? (StrengthGroup(current) == needGroup) : (needGroup == STRENGTH_FULL);
    bool ready = posOk && pitchOk && yawOk && buttonsOk;

    bool unicode = g_cvHintUnicode.BoolValue;
    char posLine[80], aimLine[96], throwName[64], text[512];
    ThrowNameEx(client, lineup.throwType, lineup.strength, throwName, sizeof(throwName));
    char posPhrase[16];
    strcopy(posPhrase, sizeof(posPhrase), atStart ? "Hint Start" : "Hint Release");

    if (posOk) {
        FormatEx(posLine, sizeof(posLine), "%T: OK", posPhrase, client);
    } else {
        float toSpot = RadToDeg(ArcTangent2(dy, dx));
        int sector = RoundToNearest(NormalizeAngle(toSpot - angles[1]) / 45.0);
        sector = (sector + 8) % 8;
        FormatEx(posLine, sizeof(posLine), "%T: %d u %s", posPhrase, client, RoundToNearest(dist),
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
    if (IsNadethrowEnabled() || needGroup != STRENGTH_FULL) {
        char buttonsLine[96];
        if (current >= 0.0 && buttonsOk) {
            FormatEx(buttonsLine, sizeof(buttonsLine), "%T: %T - OK", "Hint Buttons", client, g_StrengthPhrase[needGroup], client);
        } else if (current >= 0.0) {
            FormatEx(buttonsLine, sizeof(buttonsLine), "%T: %T (%T %T)", "Hint Buttons", client, g_StrengthPhrase[needGroup], client,
                "Hint Buttons Now", client, g_StrengthPhrase[StrengthGroup(current)], client);
        } else {
            FormatEx(buttonsLine, sizeof(buttonsLine), "%T: %T", "Hint Buttons", client, g_StrengthPhrase[needGroup], client);
        }
        Format(text, sizeof(text), "%s\n%s", text, buttonsLine);
    }
    // A weaker throw is impossible without nadethrow.
    if (needGroup != STRENGTH_FULL && !IsNadethrowEnabled()) {
        Format(text, sizeof(text), "%s\n%T", text, "Hint Need Nadethrow", client);
    }
    // A run-up throw without a start: the release point alone does not tell where to begin.
    if (!lineup.hasStart && IsRunThrow(lineup.throwType)) {
        Format(text, sizeof(text), "%s\n%T", text, "Hint No Start", client);
    }
    // A jumpthrow needs a bind; with nadethrow the alias must release the right button too.
    if (IsJumpthrowType(lineup.throwType)) {
        Format(text, sizeof(text), "%s\n%T", text, IsNadethrowEnabled() ? "Hint Alias Nadethrow" : "Hint Alias", client);
    }
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
    Hints_DrawPlaces(client, lineup, atStart, posOk, HINT_DRAW_PERIOD + 0.2);
}

// Rings: the target place (yellow, green in tolerance), the other place (smaller, light blue)
// with the run-up line between them, and the landing spot.
void Hints_DrawPlaces(int client, const Lineup lineup, bool atStart, bool posOk, float life) {
    float radius = g_cvHintPosRadius.FloatValue;
    float main[3], other[3];
    main = atStart ? g_HintStart[client] : g_HintRelease[client];
    main[2] += 2.0;
    // CSS-VERIFY: the ring size matches sm_nadepractice_hint_pos_radius.
    int color[4];
    color = g_ColorWait;
    if (posOk) {
        color = g_ColorOk;
    }
    Draw_Ring(client, main, radius * 2.0 + 8.0, life, 2.0, color);

    if (g_bHintHasStart[client]) {
        other = atStart ? g_HintRelease[client] : g_HintStart[client];
        other[2] += 2.0;
        if (GetVectorDistance(main, other) > 1.0) {
            Draw_Ring(client, other, radius + 6.0, life, 1.5, g_ColorSecond);
            float from[3], to[3];
            from = g_HintStart[client];
            to = g_HintRelease[client];
            from[2] += 3.0;
            to[2] += 3.0;
            Draw_Beam(client, from, to, life, 1.0, g_ColorSecond);
        }
    }

    if (lineup.hasDetonation) {
        float landing[3];
        landing = lineup.detonation;
        Draw_Ring(client, landing, 60.0, life, 2.0, g_NadeColor[lineup.nade]);
    }
}
