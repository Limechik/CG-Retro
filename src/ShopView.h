#import <UIKit/UIKit.h>

@class ShopView;

@protocol ShopViewDelegate <NSObject>
- (void)shopViewDidPressBack:(ShopView *)shop;
@end

// Магазин: превью оружия и курицы с ним, статы (Damage / Accuracy), вкладки Guns / Hats / Shoes / Eyes / Beak,
// прокручиваемый ряд оружия. Выбор оружия сохраняется и применяется при старте игры (+selectedWeaponIndex).
// Вёрстка — в «дизайн-координатах» 1000x590 (скриншот оригинала), масштабируется под экран.
@interface ShopView : UIView

@property (nonatomic, assign) id<ShopViewDelegate> delegate;

// Индекс выбранного оружия в weapons.plist (= weaponIndex в WeaponController), 0 по умолчанию.
+ (NSInteger)selectedWeaponIndex;

@end
