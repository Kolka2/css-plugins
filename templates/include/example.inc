#if defined _example_included
    #endinput
#endif
#define _example_included

#define EXAMPLE_LIBRARY     "example"
#define EXAMPLE_API_VERSION 1

/**
 * Активен ли сервис прямо сейчас.
 */
native bool Example_IsActive();

/**
 * Возвращает версию API загруженного плагина (сравнивать с EXAMPLE_API_VERSION).
 */
native int Example_GetApiVersion();

/**
 * Уведомление: сервис начал работу.
 */
forward void Example_OnStart();

/**
 * Уведомление: сервис закончил работу.
 */
forward void Example_OnEnd();

/**
 * Вето: сервис собирается закончить работу.
 *
 * @return  Plugin_Handled, чтобы попросить подождать; Plugin_Continue, чтобы разрешить.
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
