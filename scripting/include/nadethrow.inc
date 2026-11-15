#if defined _nadethrow_included
    #endinput
#endif
#define _nadethrow_included

#define NADETHROW_LIBRARY     "nadethrow"
#define NADETHROW_API_VERSION 1

/**
 * API version of the loaded plugin (compare with NADETHROW_API_VERSION).
 */
native int Nadethrow_GetApiVersion();

/**
 * Whether the plugin is enabled (sm_nadethrow_enabled).
 *
 * While disabled, throws are not changed and Nadethrow_OnGrenadeThrown is not called.
 */
native bool Nadethrow_IsEnabled();

/**
 * Current throw strength of a player.
 *
 * @param client    Client index (must be in game).
 * @return          0.0-1.0 while the player holds a grenade with the pin pulled
 *                  (1.0 = left click, 0.5 = left + right click, 0.0 = right click);
 *                  -1.0 otherwise. Always -1.0 for players the plugin does not
 *                  process (bots with sm_nadethrow_bots 0).
 * @error           Invalid client index or client not in game.
 */
native float Nadethrow_GetThrowStrength(int client);

/**
 * Fraction of the throw's own speed at strength 0.0 (sm_nadethrow_min_scale).
 *
 * The plugin recomputes the projectile velocity as:
 *   k   = minScale + (1 - minScale) * strength
 *   new = (v - playerVel) * k + playerVel
 * where v is the projectile velocity set by the game and playerVel is the player's
 * velocity at the moment the projectile is created.
 */
native float Nadethrow_GetMinScale();

/**
 * How many units lower the grenade is released at strength 0.0 (sm_nadethrow_z_offset).
 *
 * The release point is lowered by (1 - strength) * zOffset unless something is in the way.
 */
native float Nadethrow_GetZOffset();

/**
 * Notification: a player has thrown a grenade. Called after the projectile has been
 * adjusted (if it was), including throws with strength 1.0 and throws by bots.
 * Not called while the plugin is disabled.
 *
 * @param client        The player who threw the grenade.
 * @param projectile    Entity index of the projectile.
 * @param strength      Throw strength 0.0-1.0 (1.0 = the projectile was not changed).
 */
forward void Nadethrow_OnGrenadeThrown(int client, int projectile, float strength);

public SharedPlugin __pl_nadethrow = {
    name = NADETHROW_LIBRARY,
    file = "nadethrow.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_nadethrow_SetNTVOptional() {
    MarkNativeAsOptional("Nadethrow_GetApiVersion");
    MarkNativeAsOptional("Nadethrow_IsEnabled");
    MarkNativeAsOptional("Nadethrow_GetThrowStrength");
    MarkNativeAsOptional("Nadethrow_GetMinScale");
    MarkNativeAsOptional("Nadethrow_GetZOffset");
}
#endif
