/*
 * shown.sp - lineups shown on the map at once.
 *
 * A player shows lineups one by one (the lineup menu is a list of toggles) or all of them
 * (!all, menu). Every shown lineup within sm_nadepractice_show_radius gets a ring and a short
 * pillar at the place where to stand, in the grenade color (at most sm_nadepractice_show_max
 * nearest ones). The full hint (aim frame, text, landing ring) belongs to one lineup, the
 * selected one: walking into the ring of another shown lineup (closer than
 * sm_nadepractice_show_select_radius) selects it automatically. The selection stays when the
 * player walks away, so the hint still shows the way back; it changes at the next ring.
 */

// State (g_ShownIds, g_bShowAll, g_ShownDrawPos, SHOWN_PER_DRAW) is declared in nadepractice.sp.

void Shown_Init() {
    RegConsoleCmd("sm_all", Command_ShowAll, "Show all lineups of the map at once (toggle)");
}

void Shown_ResetClient(int client) {
    if (g_ShownIds[client] == null) {
        g_ShownIds[client] = new ArrayList();
    }
    g_ShownIds[client].Clear();
    g_bShowAll[client] = false;
    g_ShownDrawPos[client] = 0;
}

bool Shown_Is(int client, int id) {
    return g_bShowAll[client] || (g_ShownIds[client] != null && g_ShownIds[client].FindValue(id) != -1);
}

bool Shown_Any(int client) {
    return g_bShowAll[client] || (g_ShownIds[client] != null && g_ShownIds[client].Length > 0);
}

// Shows or hides one lineup.
void Shown_Set(int client, int id, bool show) {
    if (g_ShownIds[client] == null) {
        g_ShownIds[client] = new ArrayList();
    }
    int pos = g_ShownIds[client].FindValue(id);
    if (show && pos == -1) {
        g_ShownIds[client].Push(id);
    } else if (!show && pos != -1) {
        g_ShownIds[client].Erase(pos);
    }
}

// Menu toggle of one lineup. Under "show all", hiding one keeps all the others shown.
void Shown_Toggle(int client, int id) {
    bool show = !Shown_Is(client, id);
    if (g_bShowAll[client]) {
        g_bShowAll[client] = false;
        g_ShownIds[client].Clear();
        Lineup lineup;
        for (int i = 0; i < g_Lineups.Length; i++) {
            g_Lineups.GetArray(i, lineup);
            g_ShownIds[client].Push(lineup.id);
        }
    }
    Shown_Set(client, id, show);
    if (show && g_SelectedLineup[client] == 0) {
        Hints_Select(client, id);       // the first shown lineup gets the full hint at once
    } else if (!show && g_SelectedLineup[client] == id) {
        Hints_Deselect(client);
    }
    LogDebug("shown: %N lineup %d %s", client, id, show ? "on" : "off");
}

void Shown_ToggleAll(int client) {
    g_bShowAll[client] = !g_bShowAll[client];
    if (!g_bShowAll[client]) {
        g_ShownIds[client].Clear();
        Hints_Deselect(client);
    }
    g_bHints[client] = true;
    g_NextHint[client] = 0.0;
    LogDebug("shown: %N all %s", client, g_bShowAll[client] ? "on" : "off");
}

void Shown_HideAll(int client) {
    g_bShowAll[client] = false;
    g_ShownIds[client].Clear();
    Hints_Deselect(client);
    LogDebug("shown: %N all hidden", client);
}

void Shown_OnLineupDeleted(int id) {
    for (int client = 1; client <= MaxClients; client++) {
        if (g_ShownIds[client] != null) {
            Shown_Set(client, id, false);
        }
    }
}

// Where to stand for a lineup: the start, or the release point without one.
void Shown_Place(const Lineup lineup, float place[3]) {
    place = lineup.hasStart ? lineup.startOrigin : lineup.origin;
}

// Selects the shown lineup whose ring the player stands in.
void Shown_AutoSelect(int client) {
    if (!Shown_Any(client)) {
        return;
    }
    float origin[3], place[3];
    GetClientAbsOrigin(client, origin);
    float radius = g_cvShowSelectRadius.FloatValue;
    int bestId = 0;
    float bestDist = radius;
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (!Shown_Is(client, lineup.id)) {
            continue;
        }
        Shown_Place(lineup, place);
        float dx = place[0] - origin[0];
        float dy = place[1] - origin[1];
        float dist = SquareRoot(dx * dx + dy * dy);
        // Same floor only: a lineup right above or below is not "here".
        if (dist <= bestDist && FloatAbs(place[2] - origin[2]) < 72.0) {
            bestDist = dist;
            bestId = lineup.id;
        }
    }
    if (bestId != 0 && bestId != g_SelectedLineup[client]) {
        Hints_Select(client, bestId);
        LogDebug("shown: %N auto-selected lineup %d (%.0f u)", client, bestId, bestDist);
    }
}

// Rings and pillars of the shown lineups near the player, except the selected one (it has
// its own full hint). A few per update, so the per-update temp entity budget is not exceeded.
void Shown_Draw(int client) {
    if (!Shown_Any(client)) {
        return;
    }
    float origin[3], place[3];
    GetClientAbsOrigin(client, origin);
    float maxDist = g_cvShowRadius.FloatValue;

    ArrayList near = new ArrayList(2);
    any entry[2];
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (lineup.id == g_SelectedLineup[client] || !Shown_Is(client, lineup.id)) {
            continue;
        }
        Shown_Place(lineup, place);
        float dist = GetVectorDistance(origin, place);
        if (dist <= maxDist) {
            entry[0] = dist;
            entry[1] = i;
            near.PushArray(entry);
        }
    }
    near.Sort(Sort_Ascending, Sort_Float);
    int count = near.Length;
    int max = g_cvShowMax.IntValue;
    if (count > max) {
        count = max;
    }
    if (count == 0) {
        delete near;
        return;
    }

    // Each lineup is redrawn once per round of updates; a copy lives a bit longer than that.
    int rounds = (count + SHOWN_PER_DRAW - 1) / SHOWN_PER_DRAW;
    float life = float(rounds) * g_cvHintInterval.FloatValue + 0.3;
    float radius = g_cvHintPosRadius.FloatValue;
    if (g_ShownDrawPos[client] >= count) {
        g_ShownDrawPos[client] = 0;
    }
    float ground[3], top[3];
    for (int k = 0; k < SHOWN_PER_DRAW && g_ShownDrawPos[client] < count; k++) {
        near.GetArray(g_ShownDrawPos[client]++, entry);
        g_Lineups.GetArray(entry[1], lineup);
        Shown_Place(lineup, place);
        Hints_GroundBelow(place, ground);
        ground[2] += 2.0;
        top = ground;
        top[2] += 64.0;
        Draw_Ring(client, ground, radius * 2.0 + 8.0, life, 2.0, g_NadeColor[lineup.nade]);
        Draw_Beam(client, ground, top, life, 1.5, g_NadeColor[lineup.nade]);
    }
    delete near;
}

public Action Command_ShowAll(int client, int args) {
    if (CanPractice(client)) {
        Shown_ToggleAll(client);
        NP_Print(client, "%t", g_bShowAll[client] ? "Shown All On" : "Shown All Off");
    }
    return Plugin_Handled;
}
