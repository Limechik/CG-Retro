#import <UIKit/UIKit.h>

@class MenuView;

@protocol MenuViewDelegate <NSObject>
- (void)menuViewDidPressPlay:(MenuView *)menu;
@optional
- (void)menuViewDidPressShop:(MenuView *)menu;
@end

// Главное меню (UIKit поверх GL-вида): профиль слева сверху, заголовок, курица, кнопки Shop / Play / Servers.
// Вёрстка — в «дизайн-координатах» 1302x600 (как на скриншоте оригинала), масштабируется под экран.
@interface MenuView : UIView

@property (nonatomic, assign) id<MenuViewDelegate> delegate;
@property (nonatomic, copy)   NSString *playerName;      // хранится в NSUserDefaults, по тапу на плашку — правка
@property (nonatomic)         int level;                 // число в кружке слева сверху
@property (nonatomic)         float progress;            // 0...1, полоска опыта под именем
@property (nonatomic, copy)   NSString *versionString;

- (void)startAnimations;                                 // «дыхание» курицы; вызывать при показе меню
- (void)refreshOutfit;                                   // перечитать надетые предметы из магазина (шапка, очки, обувь, клюв)

@end
