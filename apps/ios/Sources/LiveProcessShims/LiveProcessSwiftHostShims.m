#import "emexDE-Swift.h"

@implementation NotificationServer

+ (void)NotifyUserWithLevel:(NotifLevel)level
               notification:(NSString *)notification
                      delay:(double)delay
{
    (void)level;
    (void)notification;
    (void)delay;
}

@end

@implementation ApplicationManagementViewController

+ (instancetype)shared
{
    static ApplicationManagementViewController *sharedController;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedController = [[ApplicationManagementViewController alloc] init];
    });
    return sharedController;
}

- (void)applicationWasInstalled:(id)app
{
    (void)app;
}

- (void)applicationWithBundleIdentifierWasUninstalled:(NSString *)bundleIdentifier
{
    (void)bundleIdentifier;
}

@end
