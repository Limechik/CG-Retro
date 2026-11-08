#import "Outfit.h"

static NSString *const kOutfitKeyPrefix = @"ChickenGunOutfit_";

NSArray *OutfitCategories(void) {
    static NSArray *cats;
    if (!cats) {
        NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"items.plist"];
        cats = [NSArray arrayWithContentsOfFile:path];
        if (!cats) cats = @[];
    }
    return cats;
}

NSArray *OutfitLayerOrder(void) { return @[ @"shoes", @"beak", @"eyes", @"hats" ]; }

NSString *OutfitSelectedID(NSString *category) {
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:[kOutfitKeyPrefix stringByAppendingString:category]];
    return [s length] ? s : @"none";
}

void OutfitSelect(NSString *category, NSString *itemID) {
    [[NSUserDefaults standardUserDefaults] setObject:itemID forKey:[kOutfitKeyPrefix stringByAppendingString:category]];
}

UIImage *OutfitLayerImage(BOOL forMenu, NSString *category, NSString *itemID, NSString *weaponID) {
    if ([itemID length] == 0 || [itemID isEqualToString:@"none"]) return nil;
    NSString *file;
    if (!forMenu && [category isEqualToString:@"beak"] && [weaponID length])
        file = [NSString stringWithFormat:@"layer_beak_%@_%@.png", itemID, weaponID];     // у каждого оружия свой слой клюва
    else
        file = [NSString stringWithFormat:@"layer_%@_%@.png", category, itemID];
    NSString *path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:(forMenu ? @"menu" : @"shop")] stringByAppendingPathComponent:file];
    return [UIImage imageWithContentsOfFile:path];
}
