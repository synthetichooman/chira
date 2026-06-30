#import <AppKit/AppKit.h>
#import "AppDelegate.h"

static BOOL ChiraActivateExistingInstanceIfNeeded(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleIdentifier.length) return NO;

    NSArray<NSRunningApplication *> *runningApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier];
    pid_t currentPID = NSProcessInfo.processInfo.processIdentifier;
    for (NSRunningApplication *runningApp in runningApps) {
        if (runningApp.processIdentifier == currentPID) continue;

        [runningApp activateWithOptions:0];
        return YES;
    }

    return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        (void)argc;
        (void)argv;

        if (ChiraActivateExistingInstanceIfNeeded()) {
            return 0;
        }

        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }

    return 0;
}
