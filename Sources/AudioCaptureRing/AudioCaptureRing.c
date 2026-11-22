#include "AudioCaptureRing.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

enum { SlotCount = 128, SlotCapacity = 32768 };

typedef struct {
    uint32_t byteCount;
    uint64_t hostTime;
    unsigned char data[SlotCapacity];
} CaptureSlot;

struct CaptureRing {
    _Atomic uint32_t readIndex;
    _Atomic uint32_t writeIndex;
    _Atomic bool droppedAudio;
    CaptureSlot slots[SlotCount];
};

CaptureRing *CaptureRingCreate(void) {
    CaptureRing *ring = malloc(sizeof(CaptureRing));
    if (ring != NULL) {
        atomic_init(&ring->readIndex, 0);
        atomic_init(&ring->writeIndex, 0);
        atomic_init(&ring->droppedAudio, false);
        // Touch the storage before Core Audio starts its real-time callback.
        for (size_t index = 0; index < SlotCount; index++) {
            volatile unsigned char *data = ring->slots[index].data;
            for (size_t offset = 0; offset < SlotCapacity; offset += 4096) {
                data[offset] = 0;
            }
        }
    }
    return ring;
}

void CaptureRingDestroy(CaptureRing *ring) {
    free(ring);
}

bool CaptureRingHasDroppedAudio(CaptureRing *ring) {
    return atomic_exchange_explicit(&ring->droppedAudio, false, memory_order_relaxed);
}

bool CaptureRingPeek(CaptureRing *ring, const void **data, uint32_t *byteCount, uint64_t *hostTime) {
    uint32_t readIndex = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    if (readIndex == atomic_load_explicit(&ring->writeIndex, memory_order_acquire)) {
        return false;
    }

    const CaptureSlot *slot = &ring->slots[readIndex % SlotCount];
    *data = slot->data;
    *byteCount = slot->byteCount;
    *hostTime = slot->hostTime;
    return true;
}

void CaptureRingConsume(CaptureRing *ring) {
    uint32_t readIndex = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    atomic_store_explicit(&ring->readIndex, readIndex + 1, memory_order_release);
}

static OSStatus captureIOProc(
    AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *inputData, const AudioTimeStamp *inputTime,
    AudioBufferList *outputData, const AudioTimeStamp *outputTime, void *context
) {
    CaptureRing *ring = context;
    if (inputData->mNumberBuffers == 0) {
        return noErr;
    }
    const AudioBuffer *buffer = &inputData->mBuffers[0];
    if (buffer->mData == NULL || buffer->mDataByteSize == 0) {
        return noErr;
    }

    uint32_t writeIndex = atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
    uint32_t readIndex = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    if (writeIndex - readIndex >= SlotCount || buffer->mDataByteSize > SlotCapacity ||
        inputData->mNumberBuffers != 1 || buffer->mNumberChannels != 1) {
        atomic_store_explicit(&ring->droppedAudio, true, memory_order_relaxed);
        return noErr;
    }

    CaptureSlot *slot = &ring->slots[writeIndex % SlotCount];
    slot->hostTime = inputTime->mFlags & kAudioTimeStampHostTimeValid
        ? inputTime->mHostTime : now->mHostTime;
    slot->byteCount = buffer->mDataByteSize;
    memcpy(slot->data, buffer->mData, buffer->mDataByteSize);
    atomic_store_explicit(&ring->writeIndex, writeIndex + 1, memory_order_release);
    return noErr;
}

OSStatus CaptureRingAttach(CaptureRing *ring, AudioObjectID device, AudioDeviceIOProcID *ioProc) {
    return AudioDeviceCreateIOProcID(device, captureIOProc, ring, ioProc);
}
