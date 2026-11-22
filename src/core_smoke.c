#include "core_smoke.h"
#include "libretro.h"

static bool smoke_environment(unsigned command, void *data)
{
    return command == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT && data &&
        *(const enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_RGB565;
}

const char *ATVSNESCoreSmoke(void)
{
    struct retro_system_info info = {0};
    if (retro_api_version() != RETRO_API_VERSION)
        return NULL;

    retro_get_system_info(&info);
    if (!info.library_name || !*info.library_name)
        return NULL;

    retro_set_environment(smoke_environment);
    retro_init();
    retro_deinit();
    return info.library_name;
}
