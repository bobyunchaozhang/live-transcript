#ifndef HUITING_BILINGUAL_ASR_H
#define HUITING_BILINGUAL_ASR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct HTBilingualASR HTBilingualASR;
typedef struct SherpaOnnxOnlineStream HTASRStream;

HTBilingualASR *ht_asr_create(
    const char *library, const char *model_directory,
    char *error, size_t error_capacity
);
void ht_asr_destroy(HTBilingualASR *engine);

const HTASRStream *ht_asr_stream_create(HTBilingualASR *engine);
void ht_asr_stream_destroy(HTBilingualASR *engine, const HTASRStream *stream);
bool ht_asr_stream_accept(
    HTBilingualASR *engine, const HTASRStream *stream,
    const float *samples, int32_t count
);
void ht_asr_stream_finish(HTBilingualASR *engine, const HTASRStream *stream);
bool ht_asr_stream_endpoint(HTBilingualASR *engine, const HTASRStream *stream);
void ht_asr_stream_reset(HTBilingualASR *engine, const HTASRStream *stream);
const char *ht_asr_stream_result(HTBilingualASR *engine, const HTASRStream *stream);
void ht_asr_result_destroy(HTBilingualASR *engine, const char *result);

#endif
