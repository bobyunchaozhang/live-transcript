#ifndef AUDIO_CAPTURE_RING_H
#define AUDIO_CAPTURE_RING_H

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct CaptureRing CaptureRing;

CaptureRing *CaptureRingCreate(void);
void CaptureRingDestroy(CaptureRing *ring);
bool CaptureRingHasDroppedAudio(CaptureRing *ring);
bool CaptureRingPeek(CaptureRing *ring, const void **data, uint32_t *byteCount, uint64_t *hostTime);
void CaptureRingConsume(CaptureRing *ring);
OSStatus CaptureRingAttach(CaptureRing *ring, AudioObjectID device, AudioDeviceIOProcID *ioProc);

#endif
