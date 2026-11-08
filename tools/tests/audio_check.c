// Проверка звуковых клипов и модели затухания.
// gcc -std=c99 -O2 -I../../src audio_check.c ../../src/AudioBank.c -o audio_check -lm ; ./audio_check Resources/audio
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <dirent.h>
#include <stdlib.h>
#include "AudioBank.h"

static int fails = 0;
#define CHECK(cond, ...) do { if (!(cond)) { fails++; printf("  НЕ ПРОШЛО: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    DIR *d = opendir(argv[1]);
    if (!d) { printf("нет папки %s\n", argv[1]); return 1; }
    struct dirent *e; int n = 0; double totalSec = 0; unsigned long bytes = 0;
    while ((e = readdir(d))) {
        size_t l = strlen(e->d_name);
        if (l < 5 || strcmp(e->d_name + l - 4, ".cga") != 0) continue;
        char path[600]; snprintf(path, sizeof path, "%s/%s", argv[1], e->d_name);
        CGAudioClip c;
        if (!cga_load(path, &c)) { CHECK(0, "%s не загрузился", e->d_name); continue; }
        float pk = cga_peak(&c), dur = cga_duration(&c);
        double sum = 0, sq = 0;
        for (unsigned i = 0; i < c.frames; i++) { double v = c.samples[i] / 32768.0; sum += v; sq += v * v; }
        double mean = sum / c.frames, rms = sqrt(sq / c.frames);
        CHECK(pk > 0.5f && pk <= 0.95f, "%s: пик %.2f вне 0.5..0.95", e->d_name, pk);
        CHECK(dur >= 0.05f && dur <= 3.01f, "%s: длительность %.2f с", e->d_name, dur);
        CHECK(fabs(mean) < 0.05, "%s: постоянная составляющая %.3f", e->d_name, mean);
        CHECK(rms > 0.01, "%s: слишком тихий (rms %.4f)", e->d_name, rms);
        CHECK(c.samples[c.frames - 1] == 0 || abs(c.samples[c.frames - 1]) < 200, "%s: клип обрывается на %d (щелчок)", e->d_name, c.samples[c.frames - 1]);
        n++; totalSec += dur; bytes += 12 + c.frames * 2; cga_free(&c);
    }
    closedir(d);
    printf("клипов %d, суммарно %.1f с, %.2f МБ\n", n, totalSec, bytes / 1048576.0);
    CHECK(n >= 20, "клипов должно быть не меньше 20");

    // затухание: монотонно убывает, 1 на ref, не меньше нуля, на maxd фиксируется
    float prev = 2;
    for (float dist = 0; dist <= 120; dist += 1) {
        float g = cgaudio_attenuation(dist, 3.0f, 80.0f, 1.2f);
        CHECK(g <= prev + 1e-6f && g > 0 && g <= 1.0f, "затухание немонотонно на %.0f м (%.4f)", dist, g);
        prev = g;
    }
    CHECK(fabsf(cgaudio_attenuation(1.0f, 3.0f, 80.0f, 1.2f) - 1.0f) < 1e-6f, "внутри ref громкость 1");
    CHECK(fabsf(cgaudio_attenuation(3.0f, 3.0f, 80.0f, 1.2f) - 1.0f) < 1e-6f, "на ref громкость 1");
    CHECK(fabsf(cgaudio_attenuation(200.0f, 3.0f, 80.0f, 1.2f) - cgaudio_attenuation(80.0f, 3.0f, 80.0f, 1.2f)) < 1e-6f, "после maxd громкость не меняется");
    printf("затухание (ref 3 м, rolloff 1.2): 10 м = %.2f, 30 м = %.2f, 80 м = %.3f\n",
           cgaudio_attenuation(10, 3, 80, 1.2f), cgaudio_attenuation(30, 3, 80, 1.2f), cgaudio_attenuation(80, 3, 80, 1.2f));
    printf(fails ? "ИТОГ: ЕСТЬ ОШИБКИ (%d)\n" : "ИТОГ: звуковые проверки пройдены\n", fails);
    return fails ? 1 : 0;
}
