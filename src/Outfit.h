#import <UIKit/UIKit.h>

// Предметы кастомизации курицы (вкладки магазина Hats / Shoes / Eyes / Beak).
// Описание — Resources/items.plist (tools/build_shop_items.py): массив категорий {key, title, items:[{id, name}]},
// первым в каждой категории идёт предмет «none» (без предмета / стандартный вид).
// Предметы — прозрачные PNG-слои, которые накладываются на спрайт курицы той же рамкой; слой выше спрайта на
// несколько пикселей (высокие шапки выходят за рамку), поэтому рамку слоя считают по размеру картинки.

NSArray *OutfitCategories(void);                              // категории из items.plist
NSArray *OutfitLayerOrder(void);                              // порядок наложения слоёв: shoes, beak, eyes, hats
NSString *OutfitSelectedID(NSString *category);               // выбранный предмет категории, по умолчанию «none»
void OutfitSelect(NSString *category, NSString *itemID);      // запомнить выбор (NSUserDefaults)

// Слой курицы для категории. forMenu — спрайт главного меню (курица с AK-47), иначе спрайт магазина, и тогда weaponID —
// id оружия в руках (нужен только для клюва, чтобы ствол оставался поверх него). nil — предмет «none» или файла нет.
UIImage *OutfitLayerImage(BOOL forMenu, NSString *category, NSString *itemID, NSString *weaponID);
