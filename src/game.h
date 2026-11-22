#ifndef ATV_SNES_GAME_H
#define ATV_SNES_GAME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ATVSNES_LIBRARY_PATH "/var/mobile/Media/ATVSNES"

typedef struct {
    void *context;
    void (*video)(void *, const uint16_t *, unsigned, unsigned, size_t);
    void (*audio)(void *, const int16_t *, size_t);
} ATVSNESOutput;

typedef struct {
    double fps;
    double sampleRate;
    char romID[65]; // SHA-256 of the ROM file, including any copier header.
} ATVSNESGameInfo;

/* The libretro core is a singleton. Open/run/close on the same thread. */
const char *ATVSNESGameOpen(const char *path, ATVSNESOutput output, ATVSNESGameInfo *info);
void ATVSNESGameRun(uint16_t player1, uint16_t player2);
void *ATVSNESGameSaveRAM(size_t *size);
size_t ATVSNESGameStateSize(void);
bool ATVSNESGameCaptureState(void *bytes, size_t size);
bool ATVSNESGameRestoreState(const void *bytes, size_t size);
void ATVSNESGameClose(void);

#endif
