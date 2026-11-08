#import "GameViewController.h"
#import "GameView.h"

@implementation GameViewController

- (void)loadView {
    self.view = [[GameView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

@end
