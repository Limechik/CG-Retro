#include "AudioBank.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

int cga_load(const char *path, CGAudioClip *out) {
    memset(out, 0, sizeof *out);
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    uint8_t hdr[12];
    if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "CGA1", 4) != 0) { fclose(f); return 0; }
    uint32_t rate, frames;
    memcpy(&rate, hdr + 4, 4); memcpy(&frames, hdr + 8, 4);
    if (rate < 8000 || rate > 96000 || frames == 0 || frames > 10u * 1000u * 1000u) { fclose(f); return 0; }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len < 0 || (size_t)len != 12 + (size_t)frames * 2) { fclose(f); return 0; }
    fseek(f, 12, SEEK_SET);
    int16_t *data = (int16_t *)malloc((size_t)frames * 2);
    if (!data || fread(data, 2, frames, f) != frames) { free(data); fclose(f); return 0; }
    fclose(f);
    out->rate = rate; out->frames = frames; out->samples = data;
    return 1;
}

void cga_free(CGAudioClip *c) {
    free(c->samples);
    memset(c, 0, sizeof *c);
}

float cga_peak(const CGAudioClip *c) {
    int pk = 0;
    for (unsigned i = 0; i < c->frames; i++) { int v = abs(c->samples[i]); if (v > pk) pk = v; }
    return pk / 32767.0f;
}

float cga_duration(const CGAudioClip *c) { return c->rate ? (float)c->frames / (float)c->rate : 0.0f; }

float cgaudio_attenuation(float d, float ref, float maxd, float rolloff) {
    if (ref <= 0) return 1.0f;
    if (d < ref) d = ref;
    if (d > maxd) d = maxd;
    return ref / (ref + rolloff * (d - ref));
}
