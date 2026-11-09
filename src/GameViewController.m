#import "GameViewController.h"
#import "GameView.h"

@implementation GameViewController

- (void)loadView {
    self.view = [[GameView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
}

- (BOOL)shouldAutorotate { return YES; }
#if __LP64__
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
#else
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
#endif

@end
