#include <stdio.h>
#include <stdlib.h>
#include <CommonCrypto/CommonDigest.h>

#include "game.h"
#include "joypads.h"
#include "libretro.h"

static ATVSNESOutput sink;
static uint16_t joypads[ATVSNES_PLAYER_COUNT];
static bool playing;

static bool environment(unsigned command, void *data)
{
    if (command == RETRO_ENVIRONMENT_SET_PIXEL_FORMAT)
        return data && *(const enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_RGB565;
    if (command == RETRO_ENVIRONMENT_GET_INPUT_BITMASKS)
        return true;
    return false;
}

static void video(const void *data, unsigned width, unsigned height, size_t pitch)
{
    if (sink.video && data && width && width <= 512 && height && height <= 512 &&
        pitch >= width * sizeof(uint16_t))
        sink.video(sink.context, data, width, height, pitch);
}

static size_t audio_batch(const int16_t *data, size_t frames)
{
    if (sink.audio && data && frames)
        sink.audio(sink.context, data, frames);
    return frames;
}

static void audio_sample(int16_t left, int16_t right)
{
    const int16_t stereo[] = { left, right };
    audio_batch(stereo, 1);
}

static void poll_input(void) {}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
    if (port >= ATVSNES_PLAYER_COUNT || device != RETRO_DEVICE_JOYPAD || index)
        return 0;
    uint16_t joypad = joypads[port];
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK)
        return (int16_t)joypad;
    return id < 16 && (joypad & (1u << id)) != 0;
}

const char *ATVSNESGameOpen(const char *path, ATVSNESOutput output, ATVSNESGameInfo *info)
{
    if (playing)
        return "Another game is already active.";
    if (!path || !info)
        return "Missing game path or timing result.";

    FILE *rom = fopen(path, "rb");
    if (!rom)
        return "Could not open the ROM.";
    long length = fseek(rom, 0, SEEK_END) == 0 ? ftell(rom) : -1;
    if (length < 32768 || length > 16 * 1024 * 1024 || fseek(rom, 0, SEEK_SET) != 0) {
        fclose(rom);
        return "Unsupported ROM size.";
    }
    void *data = malloc((size_t)length);
    if (!data || fread(data, 1, (size_t)length, rom) != (size_t)length) {
        fclose(rom);
        free(data);
        return "Could not read the ROM.";
    }
    fclose(rom);

    retro_set_environment(environment);
    retro_set_video_refresh(video);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_batch);
    retro_set_input_poll(poll_input);
    retro_set_input_state(input_state);
    retro_init();
    for (unsigned port = 0; port < ATVSNES_PLAYER_COUNT; ++port)
        retro_set_controller_port_device(port, RETRO_DEVICE_JOYPAD);

    const struct retro_game_info game = { path, data, (size_t)length, NULL };
    const bool loaded = retro_load_game(&game);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (loaded)
        CC_SHA256(data, (CC_LONG)length, digest);
    free(data);  /* the pinned core copies this during retro_load_game */
    if (!loaded) {
        retro_deinit();
        return "Snes9x could not load the ROM.";
    }

    struct retro_system_av_info av = {0};
    retro_get_system_av_info(&av);
    *info = (ATVSNESGameInfo){.fps = av.timing.fps, .sampleRate = av.timing.sample_rate};
    for (unsigned i = 0; i < sizeof(digest); ++i)
        snprintf(info->romID + i * 2, 3, "%02x", (unsigned)digest[i]);
    sink = output;
    joypads[0] = joypads[1] = 0;
    playing = true;
    return NULL;
}

void ATVSNESGameRun(uint16_t player1, uint16_t player2)
{
    if (playing) {
        joypads[0] = player1;
        joypads[1] = player2;
        retro_run();
    }
}

void *ATVSNESGameSaveRAM(size_t *size)
{
    *size = playing ? retro_get_memory_size(RETRO_MEMORY_SAVE_RAM) : 0;
    return *size ? retro_get_memory_data(RETRO_MEMORY_SAVE_RAM) : NULL;
}

size_t ATVSNESGameStateSize(void)
{
    return playing ? retro_serialize_size() : 0;
}

bool ATVSNESGameCaptureState(void *bytes, size_t size)
{
    return bytes && size && size == ATVSNESGameStateSize() && retro_serialize(bytes, size);
}

bool ATVSNESGameRestoreState(const void *bytes, size_t size)
{
    return bytes && size && size == ATVSNESGameStateSize() && retro_unserialize(bytes, size);
}

void ATVSNESGameClose(void)
{
    if (!playing)
        return;
    playing = false;
    sink = (ATVSNESOutput){0};
    joypads[0] = joypads[1] = 0;
    retro_unload_game();
    retro_deinit();
}
