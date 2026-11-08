#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Просмотрщик мешей на GLES2. Все методы вызывать при текущем EAGLContext.
@interface Renderer : NSObject

@property (nonatomic) float yaw;        // радианы
@property (nonatomic) float pitch;      // радианы
@property (nonatomic) float zoom;       // множитель расстояния камеры
@property (nonatomic) BOOL  autoSpin;

@property (nonatomic, readonly) NSUInteger meshCount;
@property (nonatomic, readonly) NSUInteger meshIndex;
@property (nonatomic, readonly) NSString  *meshName;
@property (nonatomic, readonly) NSUInteger triangleCount;
@property (nonatomic, readonly) NSString  *textureName;   // nil, если у меша нет текстуры

- (BOOL)setup;                                    // шейдеры + манифест
- (void)resizeWidth:(int)w height:(int)h;
- (void)updateWithDelta:(float)dt;
- (void)draw;
- (void)nextMesh;
- (void)prevMesh;

@end
