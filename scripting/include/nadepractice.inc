#if defined _nadepractice_included
    #endinput
#endif
#define _nadepractice_included

#define NADEPRACTICE_LIBRARY     "nadepractice"
#define NADEPRACTICE_API_VERSION 1

/**
 * Активен ли режим тренировки гранат прямо сейчас.
 *
 * Пока режим активен, он владеет деньгами и гранатами игроков, уроном,
 * числом ботов (bot_quota 0) и своими временными кварами.
 *
 * @return  true, если режим запущен (sm_nadepractice_start или автозапуск).
 */
native bool Nadepractice_IsActive();

/**
 * Возвращает версию API загруженного плагина (сравнивать с NADEPRACTICE_API_VERSION).
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
