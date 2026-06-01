#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NotifLevel) {
    NotifLevelNote = 0,
    NotifLevelWarning = 1,
    NotifLevelError = 2,
};

@interface NXOSVersion : NSObject
@property (class, nonatomic, readonly, strong) NXOSVersion *hostVersion;
@property (class, nonatomic, readonly, strong) NXOSVersion *minimumBuildVersion;
@property (class, nonatomic, readonly, strong) NXOSVersion *maximumBuildVersion;
@property (nonatomic, readonly, copy) NSString *versionString;
@property (nonatomic, readonly) double versionNumeric;
@property (nonatomic, readonly, copy) NSString *pickerVersionString;
- (instancetype)initWithVersionString:(NSString *)versionString;
@end

@interface NotificationServer : NSObject
+ (void)NotifyUserWithLevel:(NotifLevel)level
               notification:(NSString *)notification
                      delay:(double)delay;
@end

@interface ApplicationManagementViewController : NSObject
+ (instancetype)shared;
- (void)applicationWasInstalled:(id)app;
- (void)applicationWithBundleIdentifierWasUninstalled:(NSString *)bundleIdentifier;
@end
