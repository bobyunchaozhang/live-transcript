#ifndef HUITING_ECHO_DSP_H
#define HUITING_ECHO_DSP_H

#include <stddef.h>
#include <stdint.h>

enum {
    EchoSampleRate = 16000,
    EchoFrameSamples = 160,
    EchoReferenceLeadSamples = 512,
};

typedef struct EchoFilter EchoFilter;

EchoFilter *echo_filter_create(void);
void echo_filter_destroy(EchoFilter *filter);

void echo_filter_store_render(
    EchoFilter *filter, int64_t start, const int16_t *render, size_t count
);

// The residual filter adds one frame of latency. Output belongs to the
// preceding call; drive one final zero capture frame to retrieve the tail.
void echo_filter_process(
    EchoFilter *filter, int64_t capture_start, const int16_t *capture, int16_t *output
);

#endif
