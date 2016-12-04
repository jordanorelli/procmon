#import <AppKit/AppKit.h>

@interface ProcWatcher : NSObject
+ (instancetype) shared;
- (void) startWatching;
@end


