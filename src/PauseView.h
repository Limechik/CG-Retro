#import <UIKit/UIKit.h>

@class PauseView;
@protocol PauseViewDelegate <NSObject>
- (void)pauseViewDidResume:(PauseView *)view;
- (void)pauseViewDidLeave:(PauseView *)view;
- (void)pauseView:(PauseView *)view setMuted:(BOOL)muted;
@end

@interface PauseView : UIView
@property (nonatomic, assign) id<PauseViewDelegate> delegate;
- (id)initWithFrame:(CGRect)frame muted:(BOOL)muted;
@end
