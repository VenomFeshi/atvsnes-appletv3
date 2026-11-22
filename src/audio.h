#ifndef ATV_SNES_AUDIO_H
#define ATV_SNES_AUDIO_H

#include <stddef.h>
#include <stdint.h>

typedef struct ATVSNESAudio ATVSNESAudio;
ATVSNESAudio *ATVSNESAudioCreate(double sampleRate);
void ATVSNESAudioPush(ATVSNESAudio *audio, const int16_t *samples, size_t frames);
void ATVSNESAudioDestroy(ATVSNESAudio *audio);

#endif
