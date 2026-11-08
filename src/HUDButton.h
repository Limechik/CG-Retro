#import <UIKit/UIKit.h>

// Текстуры управления лежат в Resources/hud/ (tools/import_hud_textures.py берёт их из Unity-проекта оригинала).
UIImage *HUDImage(NSString *name);

static inline CGRect HUDCircle(CGFloat cx, CGFloat cy, CGFloat d) { return CGRectMake(cx - d * 0.5f, cy - d * 0.5f, d, d); }

// Круглая кнопка управления как в оригинале: тонкое кольцо (ring.png) + иконка внутри; при нажатии кольцо заливается.
@interface HUDButton : UIButton

// iconFile — имя в Resources/hud (nil — без иконки, её можно задать позже через iconImage);
// k — доля диаметра, которую занимает иконка; a — её прозрачность (в оригинале 0.56–0.68).
+ (HUDButton *)buttonWithIcon:(NSString *)iconFile iconScale:(CGFloat)k iconAlpha:(CGFloat)a;

@property (nonatomic, strong) UIImage *iconImage;

@end
