/*
 * Build-time override for SDL 2's private Android OpenSL audio header.
 * Keep this definition synchronized with the pinned SDL release.
 */
#ifndef _SDL_openslesaudio_h
#define _SDL_openslesaudio_h

#include "../../../../../external/SDL/src/SDL_internal.h"
#include "../../../../../external/SDL/include/SDL_audio.h"
#include "../../../../../external/SDL/src/audio/SDL_sysaudio.h"

#define _THIS SDL_AudioDevice *this

/* Keep five complete audio periods queued while the sixth is refilled. */
#define NUM_BUFFERS 6

struct SDL_PrivateAudioData
{
    Uint8 *mixbuff;
    int next_buffer;
    Uint8 *pmixbuff[NUM_BUFFERS];
    SDL_sem *playsem;
};

void openslES_ResumeDevices(void);
void openslES_PauseDevices(void);

#endif /* _SDL_openslesaudio_h */
