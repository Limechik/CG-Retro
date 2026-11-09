#import "AudioEngine.h"
#import "AudioBank.h"
#import <OpenAL/al.h>
#import <OpenAL/alc.h>
#import <AVFoundation/AVFoundation.h>
#include <dlfcn.h>

#define MAX_SOURCES 24
#define REF_DISTANCE 3.0f
#define MAX_DISTANCE 90.0f
#define ROLLOFF 1.2f
#define MIN_AUDIBLE 0.02f          // тише — источник не занимаем
#define MIN_REPEAT 0.02            // один и тот же звук не чаще раза в 20 мс

@implementation AudioEngine {
    ALCdevice *_device;
    ALCcontext *_context;
    ALuint _sources[MAX_SOURCES];
    int _nextSource;
    BOOL _ready, _suspended;

    NSDictionary *_table;                       // имя -> {files, gain, pitch}
    NSMutableDictionary *_buffers;              // имя клипа -> ALuint
    NSMutableDictionary *_lastPlayed;           // имя звука -> время последнего запуска
    float _listener[3];
}

@synthesize muted = _muted;

- (void)dealloc {
    if (_context) {
        alcMakeContextCurrent(_context);
        for (int i = 0; i < MAX_SOURCES; i++) { alSourceStop(_sources[i]); alDeleteSources(1, &_sources[i]); }
        for (NSNumber *b in [_buffers allValues]) { ALuint buf = [b unsignedIntValue]; alDeleteBuffers(1, &buf); }
        alcMakeContextCurrent(NULL);
        alcDestroyContext(_context);
    }
    if (_device) alcCloseDevice(_device);
}

- (BOOL)setup {
    // не прерывать музыку игрока и уважать переключатель «без звука»
    Class sessionClass = NSClassFromString(@"AVAudioSession");
    NSString * __unsafe_unretained *category = (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, "AVAudioSessionCategoryAmbient");
    if (!sessionClass || !category || !*category) {
        NSLog(@"[Audio] ambient audio session unavailable");
        return NO;
    }
    AVAudioSession *session = [sessionClass sharedInstance];
    [session setCategory:*category error:nil];
    [session setActive:YES error:nil];

    _device = alcOpenDevice(NULL);
    if (!_device) { NSLog(@"[Audio] alcOpenDevice failed"); return NO; }
    _context = alcCreateContext(_device, NULL);
    if (!_context || !alcMakeContextCurrent(_context)) { NSLog(@"[Audio] нет контекста OpenAL"); return NO; }

    alGetError();
    alGenSources(MAX_SOURCES, _sources);
    if (alGetError() != AL_NO_ERROR) { NSLog(@"[Audio] alGenSources failed"); return NO; }
    alDistanceModel(AL_INVERSE_DISTANCE_CLAMPED);

    NSString *res = [[NSBundle mainBundle] resourcePath];
    _table = [NSDictionary dictionaryWithContentsOfFile:[res stringByAppendingPathComponent:@"audio.plist"]];
    if ([_table count] == 0) { NSLog(@"[Audio] audio.plist не найден"); return NO; }

    _buffers = [NSMutableDictionary dictionary];
    _lastPlayed = [NSMutableDictionary dictionary];
    NSString *dir = [res stringByAppendingPathComponent:@"audio"];
    for (NSString *sound in _table) {
        for (NSString *clip in _table[sound][@"files"]) {
            if (_buffers[clip]) continue;
            NSString *path = [[dir stringByAppendingPathComponent:clip] stringByAppendingPathExtension:@"cga"];
            CGAudioClip c;
            if (!cga_load([path fileSystemRepresentation], &c)) { NSLog(@"[Audio] не загружен %@", path); continue; }
            ALuint buf = 0;
            alGenBuffers(1, &buf);
            alBufferData(buf, AL_FORMAT_MONO16, c.samples, (ALsizei)(c.frames * 2), (ALsizei)c.rate);
            cga_free(&c);
            if (alGetError() != AL_NO_ERROR) { NSLog(@"[Audio] alBufferData failed для %@", clip); alDeleteBuffers(1, &buf); continue; }
            _buffers[clip] = @(buf);
        }
    }
    _ready = YES;
    NSLog(@"[Audio] %lu звуков, %lu буферов", (unsigned long)[_table count], (unsigned long)[_buffers count]);
    return YES;
}

#pragma mark - Слушатель

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    if (_ready && !_suspended) alListenerf(AL_GAIN, muted ? 0.0f : 1.0f);
}

- (void)setListenerPosition:(const float *)pos yaw:(float)yaw pitch:(float)pitch {
    if (!_ready || _suspended) return;
    _listener[0] = pos[0]; _listener[1] = pos[1]; _listener[2] = pos[2];
    float cp = cosf(pitch);
    ALfloat ori[6] = { -sinf(yaw) * cp, sinf(pitch), -cosf(yaw) * cp,  0.0f, 1.0f, 0.0f };   // вперёд, вверх
    alListener3f(AL_POSITION, pos[0], pos[1], pos[2]);
    alListenerfv(AL_ORIENTATION, ori);
}

#pragma mark - Воспроизведение

- (ALuint)freeSource {
    for (int k = 0; k < MAX_SOURCES; k++) {
        int i = (_nextSource + k) % MAX_SOURCES;
        ALint state = 0;
        alGetSourcei(_sources[i], AL_SOURCE_STATE, &state);
        if (state != AL_PLAYING) { _nextSource = (i + 1) % MAX_SOURCES; return _sources[i]; }
    }
    ALuint s = _sources[_nextSource];                 // все заняты — перебиваем самый давний
    _nextSource = (_nextSource + 1) % MAX_SOURCES;
    return s;
}

- (void)play:(NSString *)name { [self play:name pos:NULL]; }
- (void)play:(NSString *)name at:(const float *)pos { [self play:name pos:pos]; }

- (void)play:(NSString *)name pos:(const float *)pos {
    if (!_ready || _muted || _suspended) return;
    NSDictionary *d = _table[name];
    if (!d) return;
    NSArray *files = d[@"files"];
    if ([files count] == 0) return;
    NSNumber *bufNum = _buffers[files[arc4random() % [files count]]];
    if (!bufNum) return;

    float gain = [d[@"gain"] floatValue];
    if (pos) {                                        // слишком далёкие и тихие звуки не играем
        float dx = pos[0] - _listener[0], dy = pos[1] - _listener[1], dz = pos[2] - _listener[2];
        float dist = sqrtf(dx * dx + dy * dy + dz * dz);
        if (gain * cgaudio_attenuation(dist, REF_DISTANCE, MAX_DISTANCE, ROLLOFF) < MIN_AUDIBLE) return;
    }
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    NSNumber *last = _lastPlayed[name];
    if (last && now - [last doubleValue] < MIN_REPEAT) return;
    _lastPlayed[name] = @(now);

    NSArray *pr = d[@"pitch"];
    float p0 = [pr[0] floatValue], p1 = [pr[1] floatValue];
    float pitch = p0 + (p1 - p0) * ((float)(arc4random() % 10000) / 10000.0f);

    ALuint src = [self freeSource];
    alSourceStop(src);
    alSourcei(src, AL_BUFFER, [bufNum unsignedIntValue]);
    alSourcef(src, AL_GAIN, gain);
    alSourcef(src, AL_PITCH, pitch);
    alSourcei(src, AL_LOOPING, AL_FALSE);
    if (pos) {
        alSourcei(src, AL_SOURCE_RELATIVE, AL_FALSE);
        alSource3f(src, AL_POSITION, pos[0], pos[1], pos[2]);
        alSourcef(src, AL_REFERENCE_DISTANCE, REF_DISTANCE);
        alSourcef(src, AL_MAX_DISTANCE, MAX_DISTANCE);
        alSourcef(src, AL_ROLLOFF_FACTOR, ROLLOFF);
    } else {
        alSourcei(src, AL_SOURCE_RELATIVE, AL_TRUE);
        alSource3f(src, AL_POSITION, 0, 0, 0);
        alSourcef(src, AL_ROLLOFF_FACTOR, 0.0f);
    }
    alSourcePlay(src);
}

#pragma mark - Приостановка

- (void)suspend {
    if (!_ready || _suspended) return;
    for (int i = 0; i < MAX_SOURCES; i++) alSourceStop(_sources[i]);
    alcMakeContextCurrent(NULL);
    alcSuspendContext(_context);
    _suspended = YES;
}

- (void)resume {
    if (!_ready || !_suspended) return;
    [[NSClassFromString(@"AVAudioSession") sharedInstance] setActive:YES error:nil];
    alcMakeContextCurrent(_context);
    alcProcessContext(_context);
    _suspended = NO;
    alListenerf(AL_GAIN, _muted ? 0.0f : 1.0f);
}

@end
