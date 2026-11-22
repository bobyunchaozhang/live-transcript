#include "EchoDSP.h"
#include "speex/speex_echo.h"
#include "speex/speex_preprocess.h"
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

enum { RenderHistorySamples = 32768, FilterSamples = 2560, DirectPathSamples = 512, PathLeadSamples = 48 };

struct EchoFilter {
    SpeexEchoState *canceller;
    SpeexPreprocessState *preprocessor;
    int16_t render[RenderHistorySamples];
    int64_t render_positions[RenderHistorySamples];
    int16_t previous_linear[EchoFrameSamples];
    int64_t previous_start;
    int64_t last_active_render;
    float previous_residual_mix;
    int64_t direct_path_delay;
    float direct_path[DirectPathSamples];
    bool has_direct_path;
    bool trusts_direct_path;
};

EchoFilter *echo_filter_create(void) {
    EchoFilter *filter = calloc(1, sizeof(*filter));
    if (!filter) {
        return NULL;
    }
    filter->canceller = speex_echo_state_init(EchoFrameSamples, FilterSamples);
    filter->preprocessor = speex_preprocess_state_init(EchoFrameSamples, EchoSampleRate);
    if (!filter->canceller || !filter->preprocessor) {
        echo_filter_destroy(filter);
        return NULL;
    }
    for (size_t i = 0; i < RenderHistorySamples; ++i) {
        filter->render_positions[i] = INT64_MIN;
    }
    filter->last_active_render = -FilterSamples - EchoFrameSamples;

    int sample_rate = EchoSampleRate;
    int noise_suppression = 0;
    int echo_suppression = -45;
    int overlap_suppression = -3;
    speex_echo_ctl(filter->canceller, SPEEX_ECHO_SET_SAMPLING_RATE, &sample_rate);
    speex_preprocess_ctl(filter->preprocessor, SPEEX_PREPROCESS_SET_ECHO_STATE, filter->canceller);
    speex_preprocess_ctl(filter->preprocessor, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &noise_suppression);
    speex_preprocess_ctl(filter->preprocessor, SPEEX_PREPROCESS_SET_ECHO_SUPPRESS, &echo_suppression);
    speex_preprocess_ctl(filter->preprocessor, SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE, &overlap_suppression);
    return filter;
}

void echo_filter_destroy(EchoFilter *filter) {
    if (filter->preprocessor) {
        speex_preprocess_state_destroy(filter->preprocessor);
    }
    if (filter->canceller) {
        speex_echo_state_destroy(filter->canceller);
    }
    free(filter);
}

static size_t render_index(int64_t position) {
    return (uint64_t)position % RenderHistorySamples;
}

static int16_t render_sample(const EchoFilter *filter, int64_t position) {
    size_t index = render_index(position);
    return filter->render_positions[index] == position ? filter->render[index] : 0;
}

void echo_filter_store_render(
    EchoFilter *filter, int64_t start, const int16_t *render, size_t count
) {
    for (size_t i = 0; i < count; ++i) {
        int64_t position = start + (int64_t)i;
        size_t index = render_index(position);
        filter->render[index] = render[i];
        filter->render_positions[index] = position;
    }
}

static float correlation(
    const EchoFilter *filter, const int16_t *signal, int64_t position,
    size_t step, float *scale
) {
    float cross = 0;
    float reference_power = 1;
    float signal_power = 1;
    for (size_t i = 0; i < EchoFrameSamples; i += step) {
        float playback = render_sample(filter, position + (int64_t)i);
        cross += signal[i] * playback;
        reference_power += playback * playback;
        signal_power += (float)signal[i] * signal[i];
    }
    *scale = cross / reference_power;
    if (reference_power < (float)(EchoFrameSamples / step) * 96 * 96) {
        return 0;
    }
    return cross * cross / (reference_power * signal_power);
}

static float find_reference(
    const EchoFilter *filter, int64_t capture_start, const int16_t *signal,
    int64_t *position, float *gain
) {
    // Find a dominant copy of playback in the uncancelled signal. This projection
    // can remove the leading audio before the long adaptive filter has converged.
    const int64_t first = capture_start + EchoReferenceLeadSamples - FilterSamples;
    const int64_t last = capture_start + EchoReferenceLeadSamples;
    int64_t rough = first;
    float best = 0;
    for (int64_t at = first; at <= last; at += 4) {
        float scale;
        float score = correlation(filter, signal, at, 4, &scale);
        if (score > best) {
            best = score;
            rough = at;
        }
    }
    if (best < 0.24f) {
        return 0;
    }

    best = 0;
    for (int64_t at = rough - 3; at <= rough + 3; ++at) {
        float scale;
        float score = correlation(filter, signal, at, 1, &scale);
        if (score > best) {
            best = score;
            *gain = scale;
            *position = at;
        }
    }
    return best;
}

static int16_t to_sample(float value) {
    return (int16_t)lrintf(fminf(INT16_MAX, fmaxf(INT16_MIN, value)));
}

static bool remove_coherent_residual(const EchoFilter *filter, int64_t capture_start, int16_t *signal) {
    int64_t position;
    float gain;
    if (find_reference(filter, capture_start, signal, &position, &gain) < 0.41f) {
        return false;
    }
    for (size_t i = 0; i < EchoFrameSamples; ++i) {
        signal[i] = to_sample(signal[i] - gain * render_sample(filter, position + (int64_t)i));
    }
    return true;
}

static bool cancel_direct_path(
    EchoFilter *filter, int64_t start, const int16_t *capture, int16_t *output
) {
    if (!filter->has_direct_path) {
        int64_t position;
        float gain;
        if (find_reference(filter, start, capture, &position, &gain) < 0.54f) {
            return false;
        }
        filter->direct_path_delay = start - position - PathLeadSamples;
        filter->direct_path[PathLeadSamples] = gain;
        filter->has_direct_path = true;
    }

    float reference[DirectPathSamples + EchoFrameSamples - 1];
    for (size_t i = 0; i < sizeof(reference) / sizeof(reference[0]); ++i) {
        reference[i] = render_sample(filter,
            start - filter->direct_path_delay + EchoFrameSamples - 1 - (int64_t)i);
    }

    // Adapt only while the predicted playback dominates. A loud independent
    // voice can then pass through unchanged by the filter's coefficient updates.
    float input_power = 1;
    float error_power = 0;
    for (size_t i = 0; i < EchoFrameSamples; ++i) {
        const float *render = reference + EchoFrameSamples - 1 - i;
        float prediction = 0;
        for (size_t tap = 0; tap < DirectPathSamples; ++tap) {
            prediction += filter->direct_path[tap] * render[tap];
        }
        float error = capture[i] - prediction;
        output[i] = to_sample(error);
        input_power += (float)capture[i] * capture[i];
        error_power += error * error;
    }
    float fraction = error_power / input_power;
    bool playback_dominant = fraction < 0.57f && input_power > EchoFrameSamples * 128.0f * 128.0f;
    if (playback_dominant) {
        filter->trusts_direct_path |= fraction < 0.16f;
        for (size_t i = 0; i < EchoFrameSamples; ++i) {
            const float *render = reference + EchoFrameSamples - 1 - i;
            float prediction = 0;
            float power = 1;
            for (size_t tap = 0; tap < DirectPathSamples; ++tap) {
                prediction += filter->direct_path[tap] * render[tap];
                power += render[tap] * render[tap];
            }
            float rate = filter->trusts_direct_path ? 0.06f : 0.20f;
            float adjustment = rate * (capture[i] - prediction) / power;
            for (size_t tap = 0; tap < DirectPathSamples; ++tap) {
                filter->direct_path[tap] += adjustment * render[tap];
            }
        }
    }
    return filter->trusts_direct_path && fraction < 1.08f;
}

void echo_filter_process(
    EchoFilter *filter, int64_t capture_start, const int16_t *capture, int16_t *output
) {
    int16_t reference[EchoFrameSamples];
    int16_t linear[EchoFrameSamples];
    // The tap's clock may lag acoustic playback slightly. Looking ahead puts
    // both small negative clock offsets and real acoustic delays in the filter.
    for (size_t i = 0; i < EchoFrameSamples; ++i) {
        int64_t position = capture_start + EchoReferenceLeadSamples + (int64_t)i;
        reference[i] = render_sample(filter, position);
        if (abs(reference[i]) >= 64) {
            filter->last_active_render = capture_start + (int64_t)i;
        }
    }
    speex_echo_cancellation(filter->canceller, capture, reference, linear);
    memcpy(output, linear, sizeof(linear));
    speex_preprocess_run(filter->preprocessor, output);

    // The residual suppressor sees the preceding frame. Favor the linear
    // result when its remaining energy indicates independent local speech.
    for (size_t i = 0; i < EchoFrameSamples; ++i) {
        float preceding = filter->previous_linear[i];
        output[i] = (int16_t)lrintf(preceding + filter->previous_residual_mix * (output[i] - preceding));
    }
    if (filter->previous_residual_mix > 0 && remove_coherent_residual(filter, filter->previous_start, output)) {
        remove_coherent_residual(filter, filter->previous_start, output);
    }
    filter->previous_start = capture_start;

    if (capture_start - filter->last_active_render >= FilterSamples) {
        memcpy(filter->previous_linear, capture, sizeof(linear));
        filter->previous_residual_mix = 0;
        return;
    }

    int16_t direct[EchoFrameSamples];
    if (cancel_direct_path(filter, capture_start, capture, direct)) {
        memcpy(filter->previous_linear, direct, sizeof(direct));
        filter->previous_residual_mix = 0.01f;
        return;
    }

    float input_power = 1;
    float linear_power = 0;
    for (size_t i = 0; i < EchoFrameSamples; ++i) {
        input_power += (float)capture[i] * capture[i];
        linear_power += (float)linear[i] * linear[i];
    }
    memcpy(filter->previous_linear, linear, sizeof(linear));
    filter->previous_residual_mix = fminf(1, fmaxf(0.12f, (0.65f - linear_power / input_power) * 2));
}
