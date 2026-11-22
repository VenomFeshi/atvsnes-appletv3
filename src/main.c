#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#include "core_smoke.h"
#include "game.h"
#include "libretro.h"

/* Diagnostic access to the pinned core's real joypad reader. */
extern uint32_t S9xReadJoypad(int32_t port);

typedef struct {
    uint32_t previous;
    unsigned frames, changes, nonblack, width, height;
    size_t audioFrames;
    bool audible;
} TestOutput;

static void test_video(void *context, const uint16_t *pixels,
                       unsigned width, unsigned height, size_t pitch)
{
    TestOutput *test = context;
    uint32_t hash = 2166136261u;
    unsigned lit = 0;
    for (unsigned y = 0; y < height; y += 4) {
        const uint16_t *row = (const uint16_t *)((const uint8_t *)pixels + y * pitch);
        for (unsigned x = 0; x < width; x += 4) {
            hash = (hash ^ row[x]) * 16777619u;
            lit |= row[x];
        }
    }
    test->changes += test->frames > 0 && test->previous != hash;
    test->nonblack += lit != 0;
    test->previous = hash;
    test->width = width;
    test->height = height;
    ++test->frames;
}

static void test_audio(void *context, const int16_t *samples, size_t frames)
{
    TestOutput *test = context;
    test->audioFrames += frames;
    for (size_t i = 0; i < frames * 2 && !test->audible; ++i)
        test->audible |= samples[i] != 0;
}

static int test_rom(const char *path)
{
    ATVSNESGameInfo info;
    TestOutput test = {0};
    ATVSNESOutput output = { &test, test_video, test_audio };
    const char *error = ATVSNESGameOpen(path, output, &info);
    if (error) {
        fprintf(stderr, "%s\n", error);
        return 1;
    }
    for (unsigned frame = 0; frame < 600; ++frame) {
        uint16_t buttons = frame >= 240 && frame % 90 < 4 ?
                           1u << RETRO_DEVICE_ID_JOYPAD_START : 0;
        ATVSNESGameRun(buttons, 0);
    }
    size_t saveSize;
    ATVSNESGameSaveRAM(&saveSize);
    ATVSNESGameClose();
    printf("ROM: %u frames (%u nonblack, %u changes), %ux%u at %.2f fps; "
           "%zu stereo PCM frames at %.0f Hz (%s); %zu bytes save RAM.\n",
           test.frames, test.nonblack, test.changes, test.width, test.height, info.fps,
           test.audioFrames, info.sampleRate, test.audible ? "nonzero" : "silent", saveSize);
    if (test.frames < 590 || !test.nonblack || !test.changes || !test.audioFrames || !test.audible)
        return 1;

    test = (TestOutput){0};
    error = ATVSNESGameOpen(path, output, &info);
    if (error) {
        fprintf(stderr, "Reopen failed: %s\n", error);
        return 1;
    }
    ATVSNESGameRun(1u << RETRO_DEVICE_ID_JOYPAD_A, 1u << RETRO_DEVICE_ID_JOYPAD_B);
    bool separate = S9xReadJoypad(0) == 0x0080 && S9xReadJoypad(1) == 0x8000 &&
                    S9xReadJoypad(2) == 0;
    ATVSNESGameRun(0, 1u << RETRO_DEVICE_ID_JOYPAD_B);
    separate &= S9xReadJoypad(0) == 0 && S9xReadJoypad(1) == 0x8000;
    ATVSNESGameRun(1u << RETRO_DEVICE_ID_JOYPAD_A, 0);
    separate &= S9xReadJoypad(0) == 0x0080 && S9xReadJoypad(1) == 0;
    ATVSNESGameClose();
    puts(separate ? "Controller ports: independent input and release passed." :
                    "Controller port isolation check failed.");
    return test.frames && separate ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc >= 3 && strcmp(argv[1], "--rom") == 0) {
        for (int i = 2; i < argc; ++i) {
            printf("Testing %s\n", argv[i]);
            if (test_rom(argv[i]) != 0)
                return 1;
        }
        return 0;
    }
    if (argc > 2) {
        fprintf(stderr, "Usage: %s [path-to-appliance-binary | --rom path [path ...]]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "Appliance load failed: %s\n", dlerror());
            return 1;
        }
        puts("Appliance binary loaded. BackRow registration requires the Apple TV UI.");
    }
    const char *name = ATVSNESCoreSmoke();
    if (!name) {
        fputs("Core metadata or API check failed.\n", stderr);
        return 1;
    }
    printf("%s: initialization and cleanup completed (no ROM loaded).\n", name);
    return 0;
}
