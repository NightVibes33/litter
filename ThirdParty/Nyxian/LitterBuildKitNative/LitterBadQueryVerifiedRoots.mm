#import <Foundation/Foundation.h>

#include "LitterBuildKitNative.h"

#ifdef LBN_ENABLE_BAD_QUERY

#import <dirent.h>
#import <errno.h>
#import <limits.h>
#import <string.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *LBNBQErrorString(int error)
{
    if(error == 0) { return @"none"; }
    const char *text = strerror(error);
    return text ? [NSString stringWithUTF8String:text] : @"unknown";
}

static BOOL LBNBQCanEnumerate(NSString *path, int *savedErrno)
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

static NSDictionary *LBNBQAccessDiagnostics(NSString *path)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    errno = 0;
    BOOL permissionWritable = access(path.fileSystemRepresentation, W_OK) == 0;
    int permissionErrno = permissionWritable ? 0 : errno;
    result[@"WritePermissionCheck"] = @(permissionWritable);
    result[@"WritePermissionErrno"] = @(permissionErrno);
    result[@"WritePermissionError"] = LBNBQErrorString(permissionErrno);

    struct statfs filesystem = {0};
    errno = 0;
    BOOL mountInspected = statfs(path.fileSystemRepresentation, &filesystem) == 0;
    int mountErrno = mountInspected ? 0 : errno;
    BOOL readOnlyFilesystem = mountInspected && (filesystem.f_flags & MNT_RDONLY) != 0;

    result[@"MountInspectionSucceeded"] = @(mountInspected);
    result[@"MountInspectionErrno"] = @(mountErrno);
    result[@"MountInspectionError"] = LBNBQErrorString(mountErrno);
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
        result[@"WriteBoundary"] = @"The current process passes the directory write-permission check; individual descendants can still enforce stricter policy.";
    }
    else if(mountInspected)
    {
        result[@"AccessMode"] = @"readable-no-write-permission";
        result[@"WriteBoundary"] = @"Enumeration succeeded, but the current process has no verified write authority for this directory.";
    }
    else
    {
        result[@"AccessMode"] = @"readable-write-status-unknown";
        result[@"WriteBoundary"] = @"Enumeration succeeded, but the filesystem mount could not be inspected.";
    }

    return result;
}

static void LBNBQRemoveLinkIfPresent(NSString *directory, NSString *name)
{
    NSString *link = [directory stringByAppendingPathComponent:name];
    struct stat status = {0};
    if(lstat(link.fileSystemRepresentation, &status) != 0 || !S_ISLNK(status.st_mode)) { return; }
    (void)unlink(link.fileSystemRepresentation);
}

static BOOL LBNBQInstallLink(NSString *directory, NSString *name, NSString *target, NSString **error)
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

static NSDictionary *LBNBQProbe(NSString *directory, NSDictionary *candidate)
{
    NSString *name = candidate[@"Name"];
    NSString *path = candidate[@"Path"];
    NSString *scope = candidate[@"Scope"] ?: @"experimental";
    NSMutableDictionary *result = [candidate mutableCopy];

    int beforeErrno = 0;
    BOOL before = LBNBQCanEnumerate(path, &beforeErrno);
    result[@"PreexistingEnumerate"] = @(before);
    result[@"PreexistingErrno"] = @(beforeErrno);
    result[@"PreexistingError"] = LBNBQErrorString(beforeErrno);

    int64_t handle = -1;
    if(!before)
    {
        // Match the Filza-27 model: create=true skips the pre-extension lstat.
        // The post-acquisition opendir/readdir verification below is authoritative.
        handle = litter_bad_query_acquire(path.fileSystemRepresentation, true, NULL, false);
        result[@"bad_query_result"] = @(handle);
    }
    else
    {
        result[@"bad_query_result"] = @"not needed";
    }

    int afterErrno = 0;
    BOOL after = LBNBQCanEnumerate(path, &afterErrno);
    result[@"EnumerateAfter"] = @(after);
    result[@"AfterErrno"] = @(afterErrno);
    result[@"AfterError"] = LBNBQErrorString(afterErrno);

    if(!after)
    {
        if(handle >= 0) { (void)litter_bad_query_release_handle(handle); }
        LBNBQRemoveLinkIfPresent(directory, name);
        result[@"HandleRetained"] = @NO;
        result[@"Status"] = @"denied";
        NSLog(@"[LitterBadQueryVerifiedRoots] denied scope=%@ path=%@ result=%lld errno=%d",
              scope, path, handle, afterErrno);
        return result;
    }

    // Successful handles are already retained by AlleyCat's process-wide native
    // BadQuery registry in litter_bad_query_acquire(). Do not release them here.
    result[@"HandleRetained"] = @(handle >= 0);
    [result addEntriesFromDictionary:LBNBQAccessDiagnostics(path)];

    NSString *linkError = nil;
    BOOL linked = LBNBQInstallLink(directory, name, path, &linkError);
    result[@"Status"] = linked ? @"verified" : @"verified-link-failed";
    result[@"LinkCreated"] = @(linked);
    if(linkError.length > 0) { result[@"LinkError"] = linkError; }

    NSLog(@"[LitterBadQueryVerifiedRoots] VERIFIED scope=%@ path=%@ handle=%lld link=%d access=%@ readonly=%@ writable=%@",
          scope, path, handle, linked, result[@"AccessMode"], result[@"FilesystemReadOnly"], result[@"EffectiveWritable"]);
    return result;
}

static void LBNBQWriteReadme(NSString *directory)
{
    NSString *text =
        @"AlleyCat bad_query verified system-root probe\n\n"
         "This folder contains only roots that this exact running AlleyCat process could enumerate after the probe.\n"
         "A bad_query return value alone is not treated as access. Every link requires a successful opendir/readdir check.\n\n"
         "Upstream-documented iOS 27 roots are tested first. Broader roots are experimental and remain absent when verification fails.\n"
         "Denied candidates are recorded in Probe Results.plist and are not exposed as links.\n"
         "Successful BadQuery handles remain live in AlleyCat's process-wide host registry until explicitly released or the process exits.\n"
         "Read-only system-volume policy, Data Protection, POSIX permissions, and sandbox policy can still restrict descendants even when a parent root is visible.\n\n"
         "This directory is inside AlleyCat's Documents container and is therefore visible to the existing /mnt/container bridge.\n";
    [text writeToFile:[directory stringByAppendingPathComponent:@"README.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void LBNBQWriteAccessStatus(NSString *directory, NSArray<NSDictionary *> *results)
{
    NSMutableString *text = [NSMutableString stringWithString:
        @"AlleyCat bad_query observed access status\n\n"
         "This report distinguishes verified directory enumeration from write authority. No files are created in the probed roots.\n\n"];

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

static NSString *LBNBQVirtualRoot(void)
{
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
            stringByAppendingPathComponent:@"[bad_query] Verified System Roots"];
}

static void LBNBQRunVerifiedRootProbe(void)
{
    if(NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27) { return; }

    NSString *directory = LBNBQVirtualRoot();
    NSError *directoryError = nil;
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&directoryError])
    {
        NSLog(@"[LitterBadQueryVerifiedRoots] directory creation failed: %@", directoryError);
        return;
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
        [results addObject:LBNBQProbe(directory, candidate)];
    }

    [results writeToFile:[directory stringByAppendingPathComponent:@"Probe Results.plist"] atomically:YES];
    LBNBQWriteAccessStatus(directory, results);
    LBNBQWriteReadme(directory);
}

__attribute__((constructor)) static void LBNBadQueryVerifiedRootsInit(void)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LBNBQRunVerifiedRootProbe();
    });
}

#endif
