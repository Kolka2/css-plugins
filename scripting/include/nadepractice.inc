#if defined _nadepractice_included
    #endinput
#endif
#define _nadepractice_included

#define NADEPRACTICE_LIBRARY     "nadepractice"
#define NADEPRACTICE_API_VERSION 1

/**
 * Whether the grenade practice mode is active right now.
 *
 * While active, the mode owns players' money and grenades, damage,
 * the bot count (bot_quota 0) and its own temporary cvars.
 *
 * @return  true if the mode is running (sm_nadepractice_start or autostart).
 */
native bool Nadepractice_IsActive();

/**
 * API version of the loaded plugin (compare with NADEPRACTICE_API_VERSION).
 */
native int Nadepractice_GetApiVersion();

public SharedPlugin __pl_nadepractice = {
    name = NADEPRACTICE_LIBRARY,
    file = "nadepractice.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_nadepractice_SetNTVOptional() {
    MarkNativeAsOptional("Nadepractice_IsActive");
    MarkNativeAsOptional("Nadepractice_GetApiVersion");
}
#endif
