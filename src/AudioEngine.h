#import <Foundation/Foundation.h>

// Звук на OpenAL: пул источников, позиционные (3D) и обычные (2D) звуки, слушатель на камере.
// Звуки задаются в audio.plist (tools/build_audio.py): имя -> клипы, усиление, диапазон высоты.
@interface AudioEngine : NSObject

@property (nonatomic) BOOL muted;

- (BOOL)setup;

// Положение и направление слушателя (yaw/pitch как у камеры). Вызывать каждый кадр.
- (void)setListenerPosition:(const float *)pos yaw:(float)yaw pitch:(float)pitch;

- (void)play:(NSString *)name;                          // «в голове» игрока: свои выстрелы, интерфейс
- (void)play:(NSString *)name at:(const float *)pos;    // 3D: громкость и стороны от положения источника

- (void)suspend;      // при сворачивании приложения / прерывании
- (void)resume;

@end
