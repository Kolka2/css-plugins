/*
 * movement.sp - per-player ring buffer of recent movement (OnPlayerRunCmdPost):
 * position, on ground or not, horizontal speed, buttons, view angles. Only while the
 * mode is active. Used to find where a throw started (the run-up or the jump) and to
 * classify jumpthrows.
 *
 * Entries are addressed by "back": 0 = the newest recorded tick. A projectile spawns
 * while the thrower's command is processed, so at that moment the newest entry is the
 * previous tick.
 */

#define MV_X        0
#define MV_Y        1
#define MV_Z        2
#define MV_TIME     3
#define MV_FLAGS    4       // MVF_* bits
#define MV_SPEED    5       // horizontal speed
#define MV_BUTTONS  6
#define MV_PITCH    7
#define MV_YAW      8
#define MV_SIZE     9

#define MVF_ONGROUND 1
#define MVF_DUCKING  2

#define MV_MAX_SECONDS 5.0  // buffer length (upper limit of sm_nadepractice_start_lookback)

ArrayList g_MoveBuf[MAXPLAYERS + 1];
int g_MoveHead[MAXPLAYERS + 1];     // index of the newest entry
int g_MoveCount[MAXPLAYERS + 1];    // valid entries

int Movement_Capacity() {
    int n = RoundToCeil(MV_MAX_SECONDS / GetTickInterval()) + 2;
    return (n > 1024) ? 1024 : n;
}

// Forget the recorded movement: after a teleport, spawn or death the old positions
// would make a false run-up.
void Movement_Clear(int client) {
    g_MoveHead[client] = -1;
    g_MoveCount[client] = 0;
}

void Movement_Record(int client, int buttons) {
    if (g_MoveBuf[client] == null) {
        g_MoveBuf[client] = new ArrayList(MV_SIZE, Movement_Capacity());
        Movement_Clear(client);
    }
    int capacity = g_MoveBuf[client].Length;

    float origin[3], velocity[3], angles[3];
    GetClientAbsOrigin(client, origin);
    GetEntityVelocity(client, velocity);
    GetClientEyeAngles(client, angles);
    int flags = GetEntityFlags(client);

    float entry[MV_SIZE];
    entry[MV_X] = origin[0];
    entry[MV_Y] = origin[1];
    entry[MV_Z] = origin[2];
    entry[MV_TIME] = GetGameTime();
    entry[MV_FLAGS] = float(((flags & FL_ONGROUND) ? MVF_ONGROUND : 0) | ((flags & FL_DUCKING) ? MVF_DUCKING : 0));
    entry[MV_SPEED] = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    entry[MV_BUTTONS] = float(buttons);
    entry[MV_PITCH] = angles[0];
    entry[MV_YAW] = angles[1];

    g_MoveHead[client] = (g_MoveHead[client] + 1) % capacity;
    g_MoveBuf[client].SetArray(g_MoveHead[client], entry);
    if (g_MoveCount[client] < capacity) {
        g_MoveCount[client]++;
    }
}

// Entry "back" ticks ago (0 = newest). false if there is no such entry.
bool Movement_Get(int client, int back, float entry[MV_SIZE]) {
    if (g_MoveBuf[client] == null || back < 0 || back >= g_MoveCount[client]) {
        return false;
    }
    int capacity = g_MoveBuf[client].Length;
    int index = (g_MoveHead[client] - back + capacity) % capacity;
    g_MoveBuf[client].GetArray(index, entry);
    return true;
}

int Movement_Buttons(const float entry[MV_SIZE]) {
    return RoundToNearest(entry[MV_BUTTONS]);
}

bool Movement_OnGround(const float entry[MV_SIZE]) {
    return (RoundToNearest(entry[MV_FLAGS]) & MVF_ONGROUND) != 0;
}

// The tick the throw buttons were released: the newest entry without attack buttons whose
// older neighbour had them. The game creates the projectile about 0.1 s after that.
// attackMask: IN_ATTACK, plus IN_ATTACK2 when nadethrow is loaded. Returns "back" or -1.
int Movement_FindRelease(int client, int attackMask, float maxAge) {
    float now = GetGameTime();
    float newer[MV_SIZE], older[MV_SIZE];
    for (int back = 0; back + 1 < g_MoveCount[client]; back++) {
        if (!Movement_Get(client, back, newer) || !Movement_Get(client, back + 1, older)) {
            break;
        }
        if (now - newer[MV_TIME] > maxAge) {
            break;
        }
        if (!(Movement_Buttons(newer) & attackMask) && (Movement_Buttons(older) & attackMask)) {
            return back;
        }
    }
    return -1;
}

// The tick jump was pressed (IN_JUMP set, not set in the older neighbour), searching from
// "from" towards older entries for at most maxTicks ticks, and also up to maxTicks newer.
// Returns the distance in ticks to "from" (0 = same tick) or -1.
int Movement_JumpPressNear(int client, int from, int maxTicks) {
    float newer[MV_SIZE], older[MV_SIZE];
    for (int d = 0; d <= maxTicks; d++) {
        for (int sign = 1; sign >= -1; sign -= 2) {
            int back = from + d * sign;
            if (sign == -1 && d == 0) {
                continue;
            }
            if (!Movement_Get(client, back, newer) || !Movement_Get(client, back + 1, older)) {
                continue;
            }
            if ((Movement_Buttons(newer) & IN_JUMP) && !(Movement_Buttons(older) & IN_JUMP)) {
                return d;
            }
        }
    }
    return -1;
}

// The newest entry on the ground, starting at "from". Returns "back" or -1.
int Movement_LastOnGround(int client, int from) {
    float entry[MV_SIZE];
    for (int back = from; back < g_MoveCount[client]; back++) {
        if (!Movement_Get(client, back, entry)) {
            break;
        }
        if (Movement_OnGround(entry)) {
            return back;
        }
    }
    return -1;
}

// Start of a run-up: the newest entry, from "from" on, that is on the ground with horizontal
// speed below maxSpeed, no older than maxAge seconds. Returns "back" or -1.
int Movement_FindRunStart(int client, int from, float maxSpeed, float maxAge) {
    float now = GetGameTime();
    float entry[MV_SIZE];
    for (int back = from; back < g_MoveCount[client]; back++) {
        if (!Movement_Get(client, back, entry) || now - entry[MV_TIME] > maxAge) {
            break;
        }
        if (Movement_OnGround(entry) && entry[MV_SPEED] < maxSpeed) {
            return back;
        }
    }
    return -1;
}

void Movement_Position(const float entry[MV_SIZE], float pos[3]) {
    pos[0] = entry[MV_X];
    pos[1] = entry[MV_Y];
    pos[2] = entry[MV_Z];
}
