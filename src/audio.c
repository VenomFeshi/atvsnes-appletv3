#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio.h"

enum { RingFrames = 4096, BufferFrames = 512, BufferCount = 3, Channels = 2 };

struct ATVSNESAudio {
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[BufferCount];
    pthread_mutex_t lock;
    size_t first, count;
    bool starting, stopping;
    int16_t samples[RingFrames * Channels];
};

static void fill(ATVSNESAudio *audio, AudioQueueBufferRef buffer)
{
    int16_t *out = buffer->mAudioData;
    for (size_t i = 0; i < BufferFrames * Channels; i += Channels) {
        if (audio->count) {
            memcpy(out + i, audio->samples + audio->first * Channels, Channels * sizeof(*out));
            audio->first = (audio->first + 1) % RingFrames;
            --audio->count;
        } else {
            out[i] = out[i + 1] = 0;
        }
    }
    buffer->mAudioDataByteSize = BufferFrames * Channels * sizeof(*out);
}

static void refill(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    ATVSNESAudio *audio = context;
    pthread_mutex_lock(&audio->lock);
    if (!audio->stopping) {
        fill(audio, buffer);
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
    pthread_mutex_unlock(&audio->lock);
}

ATVSNESAudio *ATVSNESAudioCreate(double sampleRate)
{
    if (sampleRate <= 0)
        return NULL;
    ATVSNESAudio *audio = calloc(1, sizeof(*audio));
    if (!audio)
        return NULL;
    if (pthread_mutex_init(&audio->lock, NULL) != 0) {
        free(audio);
        return NULL;
    }
    const AudioStreamBasicDescription format = {
        .mSampleRate = sampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = Channels * sizeof(int16_t),
        .mFramesPerPacket = 1,
        .mBytesPerFrame = Channels * sizeof(int16_t),
        .mChannelsPerFrame = Channels,
        .mBitsPerChannel = 16,
    };
    if (AudioQueueNewOutput(&format, refill, audio, NULL, NULL, 0, &audio->queue) != noErr)
        goto failed;
    for (size_t i = 0; i < BufferCount; ++i)
        if (AudioQueueAllocateBuffer(audio->queue, BufferFrames * format.mBytesPerFrame,
                                     &audio->buffers[i]) != noErr)
            goto failed;
    return audio;

failed:
    ATVSNESAudioDestroy(audio);
    return NULL;
}

void ATVSNESAudioPush(ATVSNESAudio *audio, const int16_t *samples, size_t frames)
{
    if (!audio)
        return;
    pthread_mutex_lock(&audio->lock);
    while (frames--) {
        if (audio->count == RingFrames) {
            audio->first = (audio->first + 1) % RingFrames;
            --audio->count;
        }
        size_t index = (audio->first + audio->count) % RingFrames * Channels;
        memcpy(audio->samples + index, samples, Channels * sizeof(*samples));
        samples += Channels;
        ++audio->count;
    }
    bool start = !audio->starting && audio->count >= BufferFrames * BufferCount;
    if (start) {
        audio->starting = true;
        for (size_t i = 0; i < BufferCount; ++i) {
            fill(audio, audio->buffers[i]);
            AudioQueueEnqueueBuffer(audio->queue, audio->buffers[i], 0, NULL);
        }
    }
    pthread_mutex_unlock(&audio->lock);
    if (start && AudioQueueStart(audio->queue, NULL) != noErr)
        fprintf(stderr, "ATVSNES: AudioQueueStart failed\n");
}

void ATVSNESAudioDestroy(ATVSNESAudio *audio)
{
    if (!audio)
        return;
    pthread_mutex_lock(&audio->lock);
    audio->stopping = true;
    pthread_mutex_unlock(&audio->lock);
    if (audio->queue)
        AudioQueueDispose(audio->queue, true);
    pthread_mutex_destroy(&audio->lock);
    free(audio);
}
