#include "BilingualASR.h"
#include "sherpa-c-api.h"
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ASR_FUNCTIONS(X) \
    X(GetVersionStr) \
    X(CreateOnlineRecognizer) \
    X(DestroyOnlineRecognizer) \
    X(CreateOnlineStream) \
    X(DestroyOnlineStream) \
    X(OnlineStreamAcceptWaveform) \
    X(IsOnlineStreamReady) \
    X(DecodeOnlineStream) \
    X(OnlineStreamInputFinished) \
    X(OnlineStreamIsEndpoint) \
    X(OnlineStreamReset) \
    X(GetOnlineStreamResultAsJson) \
    X(DestroyOnlineStreamResultJson)

struct HTBilingualASR {
    void *library;
    const SherpaOnnxOnlineRecognizer *recognizer;
#define DECLARE(name) __typeof__(&SherpaOnnx##name) name;
    ASR_FUNCTIONS(DECLARE)
#undef DECLARE
};

static bool model_path(char *path, const char *directory, const char *file) {
    int count = snprintf(path, PATH_MAX, "%s/%s", directory, file);
    return count > 0 && count < PATH_MAX;
}

HTBilingualASR *ht_asr_create(
    const char *library, const char *model_directory, char *error, size_t error_capacity
) {
    HTBilingualASR *engine = calloc(1, sizeof(*engine));
    if (!engine) {
        snprintf(error, error_capacity, "Unable to allocate the speech recognizer");
        return NULL;
    }

    engine->library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!engine->library) {
        snprintf(error, error_capacity, "%s", dlerror());
        goto fail;
    }

#define LOAD(name) \
    engine->name = (__typeof__(engine->name))dlsym(engine->library, "SherpaOnnx" #name); \
    if (!engine->name) { \
        snprintf(error, error_capacity, "Missing SherpaOnnx" #name); \
        goto fail; \
    }
    ASR_FUNCTIONS(LOAD)
#undef LOAD

    if (strcmp(engine->GetVersionStr(), "2.0.2") != 0) {
        snprintf(error, error_capacity, "Unexpected sherpa-onnx version");
        goto fail;
    }

    char encoder[PATH_MAX], decoder[PATH_MAX], joiner[PATH_MAX], tokens[PATH_MAX];
    if (!model_path(encoder, model_directory, "encoder.int8.onnx") ||
        !model_path(decoder, model_directory, "decoder.onnx") ||
        !model_path(joiner, model_directory, "joiner.int8.onnx") ||
        !model_path(tokens, model_directory, "tokens.txt")) {
        snprintf(error, error_capacity, "Invalid speech model path");
        goto fail;
    }

    SherpaOnnxOnlineRecognizerConfig config = {0};
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.transducer.encoder = encoder;
    config.model_config.transducer.decoder = decoder;
    config.model_config.transducer.joiner = joiner;
    config.model_config.tokens = tokens;
    config.model_config.provider = "cpu";
    config.model_config.num_threads = 2;
    config.decoding_method = "greedy_search";
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 2.8f;
    config.rule2_min_trailing_silence = 0.92f;
    config.rule3_min_utterance_length = 19.0f;
    engine->recognizer = engine->CreateOnlineRecognizer(&config);
    if (!engine->recognizer) {
        snprintf(error, error_capacity, "Unable to initialize the Chinese-English model");
        goto fail;
    }
    return engine;

fail:
    ht_asr_destroy(engine);
    return NULL;
}

void ht_asr_destroy(HTBilingualASR *engine) {
    if (engine->recognizer) {
        engine->DestroyOnlineRecognizer(engine->recognizer);
    }
    if (engine->library) {
        dlclose(engine->library);
    }
    free(engine);
}

const HTASRStream *ht_asr_stream_create(HTBilingualASR *engine) {
    return engine->CreateOnlineStream(engine->recognizer);
}

void ht_asr_stream_destroy(HTBilingualASR *engine, const HTASRStream *stream) {
    engine->DestroyOnlineStream(stream);
}

static bool decode(HTBilingualASR *engine, const HTASRStream *stream) {
    bool advanced = false;
    while (engine->IsOnlineStreamReady(engine->recognizer, stream)) {
        engine->DecodeOnlineStream(engine->recognizer, stream);
        advanced = true;
    }
    return advanced;
}

bool ht_asr_stream_accept(
    HTBilingualASR *engine, const HTASRStream *stream, const float *samples, int32_t count
) {
    if (count > 0) {
        engine->OnlineStreamAcceptWaveform(stream, 16000, samples, count);
    }
    return decode(engine, stream);
}

void ht_asr_stream_finish(HTBilingualASR *engine, const HTASRStream *stream) {
    float tail[16000] = {0};
    engine->OnlineStreamAcceptWaveform(stream, 16000, tail, 16000);
    engine->OnlineStreamInputFinished(stream);
    decode(engine, stream);
}

bool ht_asr_stream_endpoint(HTBilingualASR *engine, const HTASRStream *stream) {
    return engine->OnlineStreamIsEndpoint(engine->recognizer, stream) != 0;
}

void ht_asr_stream_reset(HTBilingualASR *engine, const HTASRStream *stream) {
    engine->OnlineStreamReset(engine->recognizer, stream);
}

const char *ht_asr_stream_result(HTBilingualASR *engine, const HTASRStream *stream) {
    return engine->GetOnlineStreamResultAsJson(engine->recognizer, stream);
}

void ht_asr_result_destroy(HTBilingualASR *engine, const char *result) {
    engine->DestroyOnlineStreamResultJson(result);
}
