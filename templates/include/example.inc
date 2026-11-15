#if defined _example_included
    #endinput
#endif
#define _example_included

#define EXAMPLE_LIBRARY     "example"
#define EXAMPLE_API_VERSION 1

/**
 * Whether the service is active right now.
 */
native bool Example_IsActive();

/**
 * Returns the API version of the loaded plugin (compare with EXAMPLE_API_VERSION).
 */
native int Example_GetApiVersion();

/**
 * Notification: the service has started.
 */
forward void Example_OnStart();

/**
 * Notification: the service has finished.
 */
forward void Example_OnEnd();

/**
 * Veto: the service is about to finish.
 *
 * @return  Plugin_Handled to ask it to wait; Plugin_Continue to allow.
 */
forward Action Example_OnEnding();

public SharedPlugin __pl_example = {
    name = EXAMPLE_LIBRARY,
    file = "example.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_example_SetNTVOptional() {
    MarkNativeAsOptional("Example_IsActive");
    MarkNativeAsOptional("Example_GetApiVersion");
}
#endif
