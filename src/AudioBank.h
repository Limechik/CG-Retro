// Звуковые клипы (.cga из tools/build_audio.py) и расчёт затухания. Чистый C: тестируется без OpenAL.
#ifndef AUDIOBANK_H
#define AUDIOBANK_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    unsigned rate;        // Гц
    unsigned frames;      // отсчётов (моно)
    short *samples;       // int16
} CGAudioClip;

// 1 при успехе. Проверяет заголовок и размер файла.
int cga_load(const char *path, CGAudioClip *out);
void cga_free(CGAudioClip *c);
float cga_peak(const CGAudioClip *c);        // 0..1
float cga_duration(const CGAudioClip *c);    // секунды

// Модель AL_INVERSE_DISTANCE_CLAMPED: gain = ref / (ref + rolloff * (clamp(d, ref, maxd) - ref)).
float cgaudio_attenuation(float distance, float refDist, float maxDist, float rolloff);

#ifdef __cplusplus
}
#endif
#endif
