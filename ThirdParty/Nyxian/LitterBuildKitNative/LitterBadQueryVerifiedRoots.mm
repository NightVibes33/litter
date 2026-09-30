#import <Foundation/Foundation.h>

#include "LitterBuildKitNative.h"

#include <dirent.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

static NSObject *LBNBadQueryVerifiedRootsLock(void)
{
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static BOOL LBNBadQueryCanEnumerate(NSString *path, int *savedErrno)
{
    if(savedErrno) { *savedErrno = 0; }
    if(path.length == 0 || !path.isAbsolutePath)
    {
        if(savedErrno) { *savedErrno = EINVAL; }
        return NO;
    }

    errno = 0;
    DIR *directory = opendir(path.fileSystemRepresentation);
    if(directory == NULL)
    {
        if(savedErrno) { *savedErrno = errno; }
        return NO;
    }

    errno = 0;
    (void)readdir(directory);
    int readErrno = errno;
    closedir(directory);
    if(savedErrno) { *savedErrno = readErrno; }
    return readErrno == 0;
}

static NSString *LBNBadQueryErrorString(int error)
{
    if(error == 0) { return @"none"; }
    const char *text = strerror(error);
    return text != NULL ? [NSString stringWithUTF8String:text] : @"unknown";
}

static NSDictionary *LBNBadQueryAccessDiagnostics(NSString *path)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    errno = 0;
    BOOL permissionWritable = access(path.fileSystemRepresentation, W_OK) == 0;
    int permissionErrno = permissionWritable ? 0 : errno;
    result[@"WritePermissionCheck"] = @(permissionWritable);
    result[@"WritePermissionErrno"] = @(permissionErrno);
    result[@"WritePermissionError"] = LBNBadQueryErrorString(permissionErrno);

    struct statfs filesystem = {0};
    errno = 0;
    BOOL mountInspected = statfs(path.fileSystemRepresentation, &filesystem) == 0;
    int mountErrno = mountInspected ? 0 : errno;
    BOOL readOnlyFilesystem = mountInspected && (filesystem.f_flags & MNT_RDONLY) != 0;
    result[@"MountInspectionSucceeded"] = @(mountInspected);
    result[@"MountInspectionErrno"] = @(mountErrno);
    result[@"MountInspectionError"] = LBNBadQueryErrorString(mountErrno);
    result[@"FilesystemReadOnly"] = @(readOnlyFilesystem);
    if(mountInspected)
    {
        result[@"FilesystemType"] = [NSString stringWithUTF8String:filesystem.f_fstypename] ?: @"unknown";
        result[@"MountPoint"] = [NSString stringWithUTF8String:filesystem.f_mntonname] ?: @"unknown";
        result[@"MountedFrom"] = [NSString stringWithUTF8String:filesystem.f_mntfromname] ?: @"unknown";
        result[@"MountFlags"] = @((unsigned long long)filesystem.f_flags);
    }

    BOOL effectiveWritable = permissionWritable && mountInspected && !readOnlyFilesystem;
    result[@"EffectiveWritable"] = @(effectiveWritable);
    if(readOnlyFilesystem)
    {
        result[@"AccessMode"] = @"readable-read-only-filesystem";
        result[@"WriteBoundary"] = @"The filesystem is mounted read-only. A sandbox extension can grant traversal/read access but cannot change the mount policy.";
    }
    else if(effectiveWritable)
    {
        result[@"AccessMode"] = @"readable-write-permission-present";
        result[@"WriteBoundary"] = @"The running AlleyCat process passes the directory write-permission check; individual descendants can still enforce stricter policy.";
    }
    else if(mountInspected)
    {
        result[@"AccessMode"] = @"readable-no-write-permission";
        result[@"WriteBoundary"] = @"Enumeration succeeded, but the running AlleyCat process has no verified write authority for this directory.";
    }
    else
    {
        result[@"AccessMode"] = @"readable-write-status-unknown";
        result[@"WriteBoundary"] = @"Enumeration succeeded, but the filesystem mount could not be inspected.";
    }
    return result;
}

static NSString *LBNBadQueryVerifiedRootsDirectory(void)
{
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
        stringByAppendingPathComponent:@"[bad_query] Verified System Roots"];
}

static BOOL LBNBadQueryRemoveStaleLink(NSString *directory, NSString *name, NSString **error)
{
    NSString *link = [directory stringByAppendingPathComponent:name];
    struct stat status = {0};
    if(lstat(link.fileSystemRepresentation, &status) != 0)
    {
        if(errno == ENOENT) { return YES; }
        if(error) { *error = [NSString stringWithFormat:@"lstat failed errno=%d", errno]; }
        return NO;
    }
    if(!S_ISLNK(status.st_mode)) { return YES; }
    if(unlink(link.fileSystemRepresentation) == 0) { return YES; }
    if(error) { *error = [NSString stringWithFormat:@"stale link removal failed errno=%d", errno]; }
    return NO;
}

static BOOL LBNBadQueryInstallLink(NSString *directory, NSString *name, NSString *target, NSString **error)
{
    NSString *link = [directory stringByAppendingPathComponent:name];
    struct stat status = {0};
    if(lstat(link.fileSystemRepresentation, &status) == 0)
    {
        if(!S_ISLNK(status.st_mode))
        {
            if(error) { *error = @"existing entry is not a symlink"; }
            return NO;
        }
        char current[PATH_MAX] = {0};
        ssize_t count = readlink(link.fileSystemRepresentation, current, sizeof(current) - 1);
        NSString *currentTarget = count > 0 ? [NSString stringWithUTF8String:current] : nil;
        if([currentTarget isEqualToString:target]) { return YES; }
        if(unlink(link.fileSystemRepresentation) != 0)
        {
            if(error) { *error = [NSString stringWithFormat:@"stale link removal failed errno=%d", errno]; }
            return NO;
        }
    }

    if(symlink(target.fileSystemRepresentation, link.fileSystemRepresentation) != 0)
    {
        if(error) { *error = [NSString stringWithFormat:@"symlink failed errno=%d", errno]; }
        return NO;
    }
    return YES;
}

static NSDictionary *LBNBadQueryProbeCandidate(NSString *directory, NSDictionary *candidate)
{
    NSString *name = candidate[@"Name"];
    NSString *path = candidate[@"Path"];
    NSString *scope = candidate[@"Scope"] ?: @"experimental";
    NSMutableDictionary *result = [candidate mutableCopy];

    int beforeErrno = 0;
    BOOL before = LBNBadQueryCanEnumerate(path, &beforeErrno);
    result[@"PreexistingEnumerate"] = @(before);
    result[@"PreexistingErrno"] = @(beforeErrno);
    result[@"PreexistingError"] = LBNBadQueryErrorString(beforeErrno);

    int64_t handle = -1;
    if(!before)
    {
        handle = litter_bad_query_acquire(path.fileSystemRepresentation, true, NULL, false);
        result[@"bad_query_result"] = @(handle);
    }
    else
    {
        result[@"bad_query_result"] = @"not needed";
    }

    int afterErrno = 0;
    BOOL after = LBNBadQueryCanEnumerate(path, &afterErrno);
    result[@"EnumerateAfter"] = @(after);
    result[@"AfterErrno"] = @(afterErrno);
    result[@"AfterError"] = LBNBadQueryErrorString(afterErrno);

    if(!after)
    {
        if(handle >= 0) { litter_bad_query_release_handle(handle); }
        NSString *cleanupError = nil;
        (void)LBNBadQueryRemoveStaleLink(directory, name, &cleanupError);
        result[@"Status"] = @"denied";
        if(cleanupError.length > 0) { result[@"LinkCleanupError"] = cleanupError; }
        return result;
    }

    result[@"HandleRetained"] = @(handle >= 0);
    [result addEntriesFromDictionary:LBNBadQueryAccessDiagnostics(path)];

    NSString *linkError = nil;
    BOOL linked = LBNBadQueryInstallLink(directory, name, path, &linkError);
    result[@"Status"] = linked ? @"verified" : @"verified-link-failed";
    result[@"LinkCreated"] = @(linked);
    if(linkError.length > 0) { result[@"LinkError"] = linkError; }
    return result;
}

static void LBNBadQueryWriteReadme(NSString *directory)
{
    NSString *text =
        @"AlleyCat bad_query verified system roots\n\n"
         "This folder contains only roots that this exact running AlleyCat process could enumerate after the probe.\n"
         "A bad_query return value alone is not treated as access. Every link requires a successful opendir/readdir check after acquisition.\n\n"
         "The links live inside AlleyCat's native Documents directory, so the existing native-container bridge exposes the same directory at /mnt/container/Documents/[bad_query] Verified System Roots in the AlleyCat Files UI.\n";
    [text writeToFile:[directory stringByAppendingPathComponent:@"README.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void LBNBadQueryWriteAccessStatus(NSString *directory, NSArray<NSDictionary *> *results)
{
    NSMutableString *text = [NSMutableString stringWithString:
        @"AlleyCat bad_query observed access status\n\n"];
    for(NSDictionary *result in results)
    {
        if(![result[@"EnumerateAfter"] boolValue]) { continue; }
        [text appendFormat:@"%@\n  Path: %@\n  Access: %@\n  Mount: %@ (%@)\n  Write check: %@ (errno=%@ %@)\n  Boundary: %@\n\n",
            result[@"Name"] ?: @"Unnamed root",
            result[@"Path"] ?: @"unknown",
            result[@"AccessMode"] ?: @"unknown",
            result[@"MountPoint"] ?: @"unknown",
            [result[@"FilesystemReadOnly"] boolValue] ? @"read-only" : @"not reported read-only",
            [result[@"WritePermissionCheck"] boolValue] ? @"passed" : @"failed",
            result[@"WritePermissionErrno"] ?: @0,
            result[@"WritePermissionError"] ?: @"unknown",
            result[@"WriteBoundary"] ?: @"unknown"];
    }
    [text writeToFile:[directory stringByAppendingPathComponent:@"Access Status.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

extern "C" bool litter_bad_query_refresh_verified_roots(void)
{
    @autoreleasepool
    {
        if(NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27) { return false; }

        @synchronized(LBNBadQueryVerifiedRootsLock())
        {
            NSString *directory = LBNBadQueryVerifiedRootsDirectory();
            NSError *directoryError = nil;
            if(![NSFileManager.defaultManager createDirectoryAtPath:directory
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&directoryError])
            {
                return false;
            }

            NSArray<NSDictionary *> *candidates = @[
                @{ @"Name": @"01 System Data", @"Path": @"/private/var/containers/Data/System", @"Scope": @"upstream-documented" },
                @{ @"Name": @"02 Shared SystemGroup", @"Path": @"/private/var/containers/Shared/SystemGroup", @"Scope": @"upstream-documented" },
                @{ @"Name": @"03 App Data", @"Path": @"/private/var/mobile/Containers/Data/Application", @"Scope": @"upstream-documented" },
                @{ @"Name": @"04 Internal Daemon Data", @"Path": @"/private/var/mobile/Containers/Data/InternalDaemon", @"Scope": @"upstream-documented" },
                @{ @"Name": @"05 PluginKit Data", @"Path": @"/private/var/mobile/Containers/Data/PluginKitPlugin", @"Scope": @"upstream-documented" },
                @{ @"Name": @"06 App Groups", @"Path": @"/private/var/mobile/Containers/Shared/AppGroup", @"Scope": @"upstream-documented" },
                @{ @"Name": @"20 private var", @"Path": @"/private/var", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"21 private", @"Path": @"/private", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"22 Library", @"Path": @"/Library", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"23 private etc", @"Path": @"/private/etc", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"24 Applications", @"Path": @"/Applications", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"25 System Library", @"Path": @"/System/Library", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"26 User App Bundles", @"Path": @"/private/var/containers/Bundle/Application", @"Scope": @"experimental-broader-root" },
                @{ @"Name": @"27 Mobile Library", @"Path": @"/private/var/mobile/Library", @"Scope": @"experimental-broader-root" },
            ];

            NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:candidates.count];
            for(NSDictionary *candidate in candidates)
            {
                [results addObject:LBNBadQueryProbeCandidate(directory, candidate)];
            }

            BOOL plistWritten = [results writeToFile:[directory stringByAppendingPathComponent:@"Probe Results.plist"] atomically:YES];
            LBNBadQueryWriteAccessStatus(directory, results);
            LBNBadQueryWriteReadme(directory);
            return plistWritten;
        }
    }
}

__attribute__((constructor)) static void LBNBadQueryVerifiedRootsInit(void)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        (void)litter_bad_query_refresh_verified_roots();
    });
}
