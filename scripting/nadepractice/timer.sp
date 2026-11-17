/*
 * timer.sp - movement timers (stage 13.2):
 *   !timer  - starts when the player starts moving (horizontal speed above
 *             sm_nadepractice_timer_speed) and stops when they stop (below it for
 *             sm_nadepractice_timer_stop_ticks ticks in a row, so jumps and turns do not stop it);
 *   !timer2 - manual: starts at once, the second !timer2 stops it.
 * Time is counted in ticks (OnPlayerRunCmdPost, GetGameTime), not with SourceMod timers.
 *
 * Commands follow ".timer" and ".timer2" of splewis/csgo-practice-mode (GPL-3.0);
 * the code is written anew for CS:S.
 */

#define TIMER_OFF    0
#define TIMER_AUTO   1
#define TIMER_MANUAL 2

#define TIMER_WAITING 0
#define TIMER_RUNNING 1

int g_TimerMode[MAXPLAYERS + 1];
int g_TimerState[MAXPLAYERS + 1];
float g_TimerStart[MAXPLAYERS + 1];
int g_TimerSlowTicks[MAXPLAYERS + 1];       // ticks in a row below the speed threshold
float g_TimerSlowSince[MAXPLAYERS + 1];     // when the current slow streak began

void Timer_Init() {
    RegConsoleCmd("sm_timer", Command_Timer, "Timer from the first step to the stop (again to cancel)");
    RegConsoleCmd("sm_timer2", Command_Timer2, "Manual timer: start, and again to stop");
}

void Timer_ResetClient(int client) {
    g_TimerMode[client] = TIMER_OFF;
    g_TimerState[client] = TIMER_WAITING;
    g_TimerSlowTicks[client] = 0;
}

bool Timer_IsActive(int client) {
    return g_TimerMode[client] != TIMER_OFF;
}

// Cancels a running timer. reason goes to the debug log.
void Timer_Reset(int client, const char[] reason) {
    if (g_TimerMode[client] == TIMER_OFF) {
        return;
    }
    LogDebug("timer: %N reset (%s)", client, reason);
    g_TimerMode[client] = TIMER_OFF;
    g_TimerState[client] = TIMER_WAITING;
    if (IsHuman(client) && PhraseExists("Timer Reset")) {
        NP_Print(client, "%t", "Timer Reset");
    }
    Hints_OnTimerChanged(client);
}

// A teleport by a plugin command resets the timer, except an automatic timer that is
// still waiting for the first step (teleport to a spawn, then start running).
void Timer_OnPluginTeleport(int client, const char[] reason) {
    if (g_TimerMode[client] == TIMER_AUTO && g_TimerState[client] == TIMER_WAITING) {
        return;
    }
    Timer_Reset(client, reason);
}

void Timer_Start(int client, int mode) {
    g_TimerMode[client] = mode;
    g_TimerSlowTicks[client] = 0;
    if (mode == TIMER_MANUAL) {
        g_TimerState[client] = TIMER_RUNNING;
        g_TimerStart[client] = GetGameTime();
        LogDebug("timer: %N manual start", client);
        NP_Print(client, "%t", "Timer2 Started");
    } else {
        g_TimerState[client] = TIMER_WAITING;
        LogDebug("timer: %N waiting for movement", client);
        NP_Print(client, "%t", "Timer Waiting");
    }
    Hints_OnTimerChanged(client);
}

void Timer_Stop(int client, float stopTime) {
    float result = stopTime - g_TimerStart[client];
    LogDebug("timer: %N stop, %.3f s (%s)", client, result, (g_TimerMode[client] == TIMER_MANUAL) ? "manual" : "auto");
    g_TimerMode[client] = TIMER_OFF;
    g_TimerState[client] = TIMER_WAITING;
    if (PhraseExists("Timer Result")) {
        NP_Print(client, "%t", "Timer Result", result);
    }
    Hints_OnTimerChanged(client);
}

// Every tick of a player with an automatic timer.
void Timer_OnRunCmdPost(int client) {
    if (g_TimerMode[client] != TIMER_AUTO) {
        return;
    }
    float velocity[3];
    GetEntityVelocity(client, velocity);
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    float threshold = g_cvTimerSpeed.FloatValue;
    float now = GetGameTime();

    if (g_TimerState[client] == TIMER_WAITING) {
        if (speed > threshold) {
            g_TimerState[client] = TIMER_RUNNING;
            g_TimerStart[client] = now;
            g_TimerSlowTicks[client] = 0;
            LogDebug("timer: %N started (speed %.1f)", client, speed);
        }
        return;
    }
    if (speed > threshold) {
        g_TimerSlowTicks[client] = 0;
        return;
    }
    if (g_TimerSlowTicks[client] == 0) {
        g_TimerSlowSince[client] = now;
    }
    g_TimerSlowTicks[client]++;
    if (g_TimerSlowTicks[client] >= g_cvTimerStopTicks.IntValue) {
        // The run ended when the slow streak began.
        Timer_Stop(client, g_TimerSlowSince[client]);
    }
}

// Line for the hint panel, empty if no timer runs.
void Timer_HintLine(int client, char[] buffer, int maxlen) {
    buffer[0] = '\0';
    if (g_TimerMode[client] == TIMER_OFF || !PhraseExists("Timer Hint Waiting") || !PhraseExists("Timer Hint Running")) {
        return;
    }
    if (g_TimerState[client] == TIMER_WAITING) {
        FormatEx(buffer, maxlen, "%T", "Timer Hint Waiting", client);
    } else {
        FormatEx(buffer, maxlen, "%T", "Timer Hint Running", client, GetGameTime() - g_TimerStart[client]);
    }
}

public Action Command_Timer(int client, int args) {
    if (!CanPractice(client)) {
        return Plugin_Handled;
    }
    if (g_TimerMode[client] != TIMER_OFF) {
        Timer_Reset(client, "!timer again");
    } else {
        Timer_Start(client, TIMER_AUTO);
    }
    return Plugin_Handled;
}

public Action Command_Timer2(int client, int args) {
    if (!CanPractice(client)) {
        return Plugin_Handled;
    }
    if (g_TimerMode[client] == TIMER_MANUAL) {
        Timer_Stop(client, GetGameTime());
    } else {
        if (g_TimerMode[client] != TIMER_OFF) {
            Timer_Reset(client, "!timer2 replaces !timer");
        }
        Timer_Start(client, TIMER_MANUAL);
    }
    return Plugin_Handled;
}
