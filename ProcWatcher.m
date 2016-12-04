#include "_cgo_export.h"
#import "ProcWatcher.h"

@implementation ProcWatcher

+ (instancetype) shared {
    static id sharedInstance;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        sharedInstance = [ProcWatcher new];
    });
    return sharedInstance;
}

- (void) startWatching {
    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    NSNotificationCenter* notifications = [workspace notificationCenter];

    void (^handleAppLaunch) (NSNotification*) = ^(NSNotification* note) {
        NSDictionary* info = note.userInfo;
        NSRunningApplication* app = info[NSWorkspaceApplicationKey];
        NSString* bundleId = app.bundleIdentifier;

        AppStarted((GoString){bundleId.UTF8String, bundleId.length});
    };

    id observerLaunch = [notifications
        addObserverForName: NSWorkspaceDidLaunchApplicationNotification
                    object: workspace
                     queue: [NSOperationQueue mainQueue]
                usingBlock: handleAppLaunch];

    void (^handleAppTerminate) (NSNotification*) = ^(NSNotification* note) {
        NSDictionary* info = note.userInfo;
        NSRunningApplication* app = info[NSWorkspaceApplicationKey];
        NSString* bundleId = app.bundleIdentifier;

        AppEnded((GoString){bundleId.UTF8String, bundleId.length});
    };

    id observerTerminate = [notifications
        addObserverForName: NSWorkspaceDidTerminateApplicationNotification
                    object: workspace
                     queue: [NSOperationQueue mainQueue]
                usingBlock: handleAppTerminate];
}

@end
