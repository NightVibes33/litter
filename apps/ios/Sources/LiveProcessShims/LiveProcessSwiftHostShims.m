#import "emexDE-Swift.h"

@implementation NXBootstrap {
    NSURL *_rootURL;
}

+ (instancetype)shared
{
    static NXBootstrap *bootstrap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bootstrap = [[NXBootstrap alloc] init];
    });
    return bootstrap;
}

- (NSURL *)rootURL
{
    if(_rootURL == nil)
    {
        NSString *documentsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        _rootURL = [NSURL fileURLWithPath:documentsPath isDirectory:YES];
    }
    return _rootURL;
}

- (NSURL *)sdkURL
{
    return [self.rootURL URLByAppendingPathComponent:@"SDK/iPhoneOS26.5.sdk"];
}

- (NSURL *)includeURL
{
    return [self.rootURL URLByAppendingPathComponent:@"Include"];
}

- (NSURL *)projectsURL
{
    return [self.rootURL URLByAppendingPathComponent:@"Projects"];
}

- (NSURL *)cacheURL
{
    return [self.rootURL URLByAppendingPathComponent:@"Cache"];
}

- (NSURL *)bootstrapPlistURL
{
    return [self.rootURL URLByAppendingPathComponent:@"bootstrap.plist"];
}

- (NSURL *)swiftURL
{
    return [self.rootURL URLByAppendingPathComponent:@"swift"];
}

- (NSURL *)swiftModuleCacheURL
{
    return [self.rootURL URLByAppendingPathComponent:@"ModuleCache"];
}

- (UInt64)version
{
    return NXBOOTSTRAP_NEWEST_VERSION;
}

- (BOOL)isInstalled
{
    return YES;
}

- (void)bootstrap
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for(NSURL *url in @[self.rootURL, self.projectsURL, self.cacheURL, self.swiftModuleCacheURL])
    {
        [fileManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSString *)relativeToBootstrapWithAbsolutePath:(NSString *)path
{
    NSString *rootPath = self.rootURL.path;
    if(![path hasPrefix:rootPath]) return nil;
    NSString *relativePath = [path substringFromIndex:rootPath.length];
    if([relativePath hasPrefix:@"/"])
    {
        relativePath = [relativePath substringFromIndex:1];
    }
    return relativePath;
}

- (void)clearURL:(NSURL *)url
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtURL:url error:nil];
    [fileManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)waitTillDone
{
}

- (BOOL)isNewest
{
    return YES;
}

@end

@implementation NXOSVersion

static double NXOSVersionNumericValue(NSString *versionString)
{
    NSArray<NSString *> *parts = [versionString componentsSeparatedByString:@"."];
    NSInteger major = parts.count > 0 ? parts[0].integerValue : 0;
    NSInteger minor = parts.count > 1 ? parts[1].integerValue : 0;
    NSInteger patch = parts.count > 2 ? parts[2].integerValue : 0;
    return (double)(major * 1000000 + minor * 1000 + patch);
}

static BOOL NXOSVersionStringIsValid(NSString *versionString)
{
    if(versionString.length == 0) return NO;
    NSArray<NSString *> *parts = [versionString componentsSeparatedByString:@"."];
    if(parts.count < 1 || parts.count > 3) return NO;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for(NSString *part in parts)
    {
        if(part.length == 0) return NO;
        if([part rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound) return NO;
    }
    return YES;
}

+ (instancetype)hostVersion
{
    static NXOSVersion *version;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
        NSString *versionString = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)osVersion.majorVersion, (long)osVersion.minorVersion, (long)osVersion.patchVersion];
        version = [[NXOSVersion alloc] initWithVersionString:versionString];
    });
    return version;
}

+ (instancetype)minimumBuildVersion
{
    return [[NXOSVersion alloc] initWithVersionString:@"18.0"];
}

+ (instancetype)maximumBuildVersion
{
    return [[NXOSVersion alloc] initWithVersionString:@"26.0"];
}

- (instancetype)init
{
    return [self initWithVersionString:[[self.class hostVersion] versionString]];
}

- (instancetype)initWithVersionString:(NSString *)versionString
{
    self = [super init];
    if(self)
    {
        NSString *validatedVersionString = NXOSVersionStringIsValid(versionString) ? versionString : @"18.0";
        _versionString = [validatedVersionString copy];
        _versionNumeric = NXOSVersionNumericValue(_versionString);
        _pickerVersionString = [_versionString copy];
    }
    return self;
}

- (NSString *)description
{
    return [@"iOS " stringByAppendingString:self.versionString];
}

- (BOOL)isEqual:(id)object
{
    if(![object isKindOfClass:[NXOSVersion class]]) return NO;
    return self.versionNumeric == [(NXOSVersion *)object versionNumeric];
}

- (NSUInteger)hash
{
    return (NSUInteger)self.versionNumeric;
}

@end

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
