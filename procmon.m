#include "procmon.h"
#import "_cgo_export.h"
#import <AppKit/AppKit.h>

@interface ProcWatcher : NSObject
+ (instancetype) shared;
- (void) applicationDidLaunch:(NSNotification*) notification;
@end

@implementation ProcWatcher

+ (instancetype) shared {
    static id sharedInstance;
    static dispatch_once_t predicate;

    NSLog(@"ProcWatcher shared instance accessed");

    dispatch_once(&predicate, ^{
        TheGoFunc((GoString){"dispatch", 8});
        sharedInstance = [ProcWatcher new];
    });
    return sharedInstance;
}

- (void) applicationDidLaunch:(NSNotification*) notification {
    NSDictionary* info = notification.userInfo;
    NSRunningApplication* app = info[NSWorkspaceApplicationKey];
    NSString* bundleId = app.bundleIdentifier;

    NSLog(@"application launched: %@", bundleId);

    TheGoFunc((GoString){bundleId.UTF8String, bundleId.length});
}

@end

void TheCFunc() {
    NSLog(@"current run loop: %@", [NSRunLoop currentRunLoop]);
    NSLog(@"current run loop mode: %@", [[NSRunLoop currentRunLoop] currentMode]);
    NSLog(@"current run loop mode: %@", [[NSRunLoop currentRunLoop] currentMode]);

    if ([NSThread isMainThread]) {
        NSLog(@"TheCFunc is in the main thread");
    } else {
        NSLog(@"TheCFunc is NOT in the main thread");
    }

    NSLog(@"hi from nslog");
    TheGoFunc((GoString){"hi", 2});

    NSArray* running = [[NSWorkspace sharedWorkspace] runningApplications];
    NSLog(@"%@", running);
    
    ProcWatcher* pw = [ProcWatcher shared];

    NSNotificationCenter* notifications = [[NSWorkspace sharedWorkspace] notificationCenter];
   
    [notifications
        addObserver: pw
        selector: @selector(applicationDidLaunch:)
        name: NSWorkspaceDidLaunchApplicationNotification object: nil];

    NSLog(@"thing has finished");

    [[NSRunLoop currentRunLoop] run];
}
