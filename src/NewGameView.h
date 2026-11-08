#import <UIKit/UIKit.h>

@class NewGameView;

@protocol NewGameViewDelegate <NSObject>
- (void)newGameViewDidPressBack:(NewGameView *)v;
// sceneFile — имя из scenes.txt («Dust2.cgs»); mode — CGGameMode (0 — все против всех, 1 — командный бой).
- (void)newGameView:(NewGameView *)v didSelectMap:(NSString *)sceneFile mode:(int)mode;
@end

// Экран «Новая игра» (кнопка Play в меню): выбор режима и карты. Тап по карте — начать игру.
// Вёрстка в «дизайн-координатах» 1170x500 (скриншот оригинала); на высоких экранах (iPhone 5, iPad) карточки
// растут до 1.45x, свободное место делится между блоками.
@interface NewGameView : UIView

@property (nonatomic, assign) id<NewGameViewDelegate> delegate;

+ (int)savedMode;                    // последний выбранный режим (NSUserDefaults)

@end
