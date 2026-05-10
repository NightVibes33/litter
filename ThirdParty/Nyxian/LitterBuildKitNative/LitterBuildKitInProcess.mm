#import <Foundation/Foundation.h>
#import <MobileDevelopmentKit/MDKDriver.h>
#import <MobileDevelopmentKit/MDKJob.h>
#import <MobileDevelopmentKit/MDKDiagnostic.h>

#include <zlib.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>

static NSString *LBIString(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static char *LBICopyResponseWithArtifacts(int exitCode, NSString *status, NSString *log, NSArray<NSDictionary *> *artifacts)
{
    NSMutableDictionary *response = [@{@"exitCode": @(exitCode), @"status": status ?: @"unknown", @"log": log ?: @""} mutableCopy];
    if(artifacts.count > 0) { response[@"artifacts"] = artifacts; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"exitCode\":70,\"status\":\"response-encode-failed\",\"log\":\"could not encode response\"}";
    return strdup(json.UTF8String);
}

static char *LBICopyResponse(int exitCode, NSString *status, NSString *log)
{
    return LBICopyResponseWithArtifacts(exitCode, status, log, nil);
}

static NSArray<NSString *> *LBIWords(NSString *raw)
{
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    [[raw componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] enumerateObjectsUsingBlock:^(NSString *part, NSUInteger idx, BOOL *stop) {
        if(part.length > 0) { [items addObject:part]; }
    }];
    return items;
}

static NSString *LBIDiagnosticText(NSArray<MDKDiagnostic *> *diagnostics)
{
    NSMutableString *text = [NSMutableString string];
    for(MDKDiagnostic *diagnostic in diagnostics)
    {
        NSString *level = @"diagnostic";
        switch(diagnostic.level)
        {
            case CCDiagnosticLevelError: level = @"error"; break;
            case CCDiagnosticLevelWarning: level = @"warning"; break;
            case CCDiagnosticLevelNote: level = @"note"; break;
            case CCDiagnosticLevelRemark: level = @"remark"; break;
            default: break;
        }
        [text appendFormat:@"%@: %@\n", level, diagnostic.message ?: @""];
    }
    return text;
}

static int LBIRunSwiftDriver(NSArray<NSString *> *arguments, NSMutableString *log)
{
    [log appendFormat:@"swift driver args: %@\n", [arguments componentsJoinedByString:@" "]];
    MDKDriver *driver = [MDKDriver driverWithArguments:arguments withType:CCDriverTypeSwift];
    if(driver == nil)
    {
        [log appendString:@"Could not create Nyxian Swift driver.\n"];
        return 70;
    }
    NSArray<MDKJob *> *jobs = [driver generateJobs];
    if(jobs.count == 0)
    {
        [log appendString:@"Nyxian Swift driver produced no jobs.\n"];
        return 70;
    }
    int exitCode = 0;
    for(MDKJob *job in jobs)
    {
        NSArray<MDKDiagnostic *> *diagnostics = nil;
        NSString *mainSource = nil;
        BOOL ok = [job executeJobWithOutDiagnostics:&diagnostics withOutMainSource:&mainSource];
        [log appendFormat:@"job type=%u source=%@ ok=%@\n", job.type, mainSource ?: @"", ok ? @"yes" : @"no"];
        if(diagnostics.count > 0) { [log appendString:LBIDiagnosticText(diagnostics)]; }
        if(!ok) { exitCode = 1; }
    }
    return exitCode;
}

static NSDictionary *LBIProjectManifest(NSString *hostProjectPath, NSMutableString *log)
{
    NSData *data = [NSData dataWithContentsOfFile:hostProjectPath];
    if(data == nil)
    {
        [log appendFormat:@"Could not read host project manifest: %@\n", hostProjectPath];
        return nil;
    }
    NSError *error = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if(![manifest isKindOfClass:NSDictionary.class])
    {
        [log appendFormat:@"Could not decode host project manifest: %@\n", error.localizedDescription ?: @"unknown error"];
        return nil;
    }
    return manifest;
}

static NSArray<NSString *> *LBISwiftSources(NSDictionary *manifest, NSString *hostWorkDir)
{
    NSMutableArray<NSString *> *sources = [NSMutableArray array];
    NSArray *roots = [manifest[@"sources"] isKindOfClass:NSArray.class] ? manifest[@"sources"] : @[];
    NSFileManager *fm = NSFileManager.defaultManager;
    for(NSString *root in roots)
    {
        NSString *hostRoot = [root hasPrefix:@"/"] ? root : [hostWorkDir stringByAppendingPathComponent:root];
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:hostRoot];
        for(NSString *relative in enumerator)
        {
            if([relative.pathExtension.lowercaseString isEqualToString:@"swift"])
            {
                [sources addObject:[hostRoot stringByAppendingPathComponent:relative]];
            }
        }
        BOOL isDirectory = NO;
        if([fm fileExistsAtPath:hostRoot isDirectory:&isDirectory] && !isDirectory && [hostRoot.pathExtension.lowercaseString isEqualToString:@"swift"])
        {
            [sources addObject:hostRoot];
        }
    }
    return sources;
}


static NSString *LBIManifestString(NSDictionary *manifest, NSString *key, NSString *fallback)
{
    id value = manifest[key];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : fallback;
}

static void LBIAppendLE16(NSMutableData *data, uint16_t value)
{
    uint8_t bytes[2] = { (uint8_t)(value & 0xff), (uint8_t)((value >> 8) & 0xff) };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void LBIAppendLE32(NSMutableData *data, uint32_t value)
{
    uint8_t bytes[4] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 24) & 0xff)
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static BOOL LBIWriteInfoPlist(NSDictionary *manifest, NSString *appDir, NSString *productName, NSString *deployment, NSMutableString *log)
{
    NSString *bundleIdentifier = LBIManifestString(manifest, @"bundleIdentifier", @"com.sigkitten.litter.generated");
    NSDictionary *plist = @{
        @"CFBundleDevelopmentRegion": @"en",
        @"CFBundleExecutable": productName,
        @"CFBundleIdentifier": bundleIdentifier,
        @"CFBundleInfoDictionaryVersion": @"6.0",
        @"CFBundleName": productName,
        @"CFBundlePackageType": @"APPL",
        @"CFBundleShortVersionString": @"1.0",
        @"CFBundleVersion": @"1",
        @"CFBundleSupportedPlatforms": @[@"iPhoneOS"],
        @"LSRequiresIPhoneOS": @YES,
        @"MinimumOSVersion": deployment,
        @"UIDeviceFamily": @[@1, @2]
    };
    NSString *path = [appDir stringByAppendingPathComponent:@"Info.plist"];
    BOOL ok = [plist writeToFile:path atomically:YES];
    [log appendFormat:@"%@ Info.plist: %@\n", ok ? @"Wrote" : @"Could not write", path];
    return ok;
}

static BOOL LBICopyManifestResources(NSDictionary *manifest, NSString *hostWorkDir, NSString *appDir, NSMutableString *log)
{
    NSArray *resources = [manifest[@"resources"] isKindOfClass:NSArray.class] ? manifest[@"resources"] : @[];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSUInteger copied = 0;
    for(NSString *resource in resources)
    {
        NSString *source = [resource hasPrefix:@"/"] ? resource : [hostWorkDir stringByAppendingPathComponent:resource];
        BOOL isDirectory = NO;
        if(![fm fileExistsAtPath:source isDirectory:&isDirectory])
        {
            [log appendFormat:@"Skipped missing resource: %@\n", source];
            continue;
        }
        NSString *destination = [appDir stringByAppendingPathComponent:source.lastPathComponent];
        [fm removeItemAtPath:destination error:nil];
        NSError *copyError = nil;
        if([fm copyItemAtPath:source toPath:destination error:&copyError])
        {
            copied += 1;
        }
        else
        {
            [log appendFormat:@"Could not copy resource %@: %@\n", source, copyError.localizedDescription ?: @"unknown error"];
        }
    }
    [log appendFormat:@"Copied staged resources: %lu\n", (unsigned long)copied];
    return YES;
}

static NSArray<NSDictionary *> *LBICollectZipEntries(NSString *appDir, NSString *productName, NSMutableString *log)
{
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:appDir];
    for(NSString *relative in enumerator)
    {
        NSString *path = [appDir stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        if(![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) { continue; }
        NSString *entryName = [NSString stringWithFormat:@"Payload/%@.app/%@", productName, relative];
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil] ?: @{};
        NSNumber *permissions = attributes[NSFilePosixPermissions] ?: @0644;
        [entries addObject:@{@"path": path, @"name": entryName, @"mode": permissions}];
    }
    [log appendFormat:@"IPA zip entries: %lu\n", (unsigned long)entries.count];
    return entries;
}

static BOOL LBIWriteStoredZip(NSString *appDir, NSString *productName, NSString *ipaPath, NSMutableString *log)
{
    NSArray<NSDictionary *> *entries = LBICollectZipEntries(appDir, productName, log);
    if(entries.count == 0)
    {
        [log appendString:@"Cannot package IPA: app bundle has no files.\n"];
        return NO;
    }

    NSMutableData *zip = [NSMutableData data];
    NSMutableData *central = [NSMutableData data];
    NSUInteger writtenEntries = 0;
    for(NSDictionary *entry in entries)
    {
        NSString *path = entry[@"path"];
        NSString *name = entry[@"name"];
        NSData *fileData = [NSData dataWithContentsOfFile:path];
        NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
        if(fileData == nil || nameData.length == 0 || fileData.length > UINT32_MAX)
        {
            [log appendFormat:@"Skipped unpackageable file: %@\n", path];
            continue;
        }
        uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
        crc = (uint32_t)crc32(crc, (const Bytef *)fileData.bytes, (uInt)fileData.length);
        uint32_t size = (uint32_t)fileData.length;
        uint32_t offset = (uint32_t)zip.length;
        uint32_t mode = ((uint32_t)[entry[@"mode"] unsignedShortValue]) << 16;

        LBIAppendLE32(zip, 0x04034b50);
        LBIAppendLE16(zip, 20);
        LBIAppendLE16(zip, 0);
        LBIAppendLE16(zip, 0);
        LBIAppendLE16(zip, 0);
        LBIAppendLE16(zip, 0);
        LBIAppendLE32(zip, crc);
        LBIAppendLE32(zip, size);
        LBIAppendLE32(zip, size);
        LBIAppendLE16(zip, (uint16_t)nameData.length);
        LBIAppendLE16(zip, 0);
        [zip appendData:nameData];
        [zip appendData:fileData];

        LBIAppendLE32(central, 0x02014b50);
        LBIAppendLE16(central, 0x031E);
        LBIAppendLE16(central, 20);
        LBIAppendLE16(central, 0);
        LBIAppendLE16(central, 0);
        LBIAppendLE16(central, 0);
        LBIAppendLE16(central, 0);
        LBIAppendLE32(central, crc);
        LBIAppendLE32(central, size);
        LBIAppendLE32(central, size);
        LBIAppendLE16(central, (uint16_t)nameData.length);
        LBIAppendLE16(central, 0);
        LBIAppendLE16(central, 0);
        LBIAppendLE16(central, 0);
        LBIAppendLE16(central, 0);
        LBIAppendLE32(central, mode);
        LBIAppendLE32(central, offset);
        [central appendData:nameData];
        writtenEntries += 1;
    }

    if(writtenEntries == 0)
    {
        [log appendString:@"Cannot package IPA: no files were written to the zip.\n"];
        return NO;
    }

    uint32_t centralOffset = (uint32_t)zip.length;
    [zip appendData:central];
    LBIAppendLE32(zip, 0x06054b50);
    LBIAppendLE16(zip, 0);
    LBIAppendLE16(zip, 0);
    LBIAppendLE16(zip, (uint16_t)writtenEntries);
    LBIAppendLE16(zip, (uint16_t)writtenEntries);
    LBIAppendLE32(zip, (uint32_t)central.length);
    LBIAppendLE32(zip, centralOffset);
    LBIAppendLE16(zip, 0);

    NSString *parent = ipaPath.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = [zip writeToFile:ipaPath atomically:YES];
    [log appendFormat:@"%@ unsigned IPA: %@\n", ok ? @"Wrote" : @"Could not write", ipaPath];
    return ok;
}

extern "C" char *LBNRunInProcessBuildKit(NSDictionary *request, NSString *requestPath)
{
    @autoreleasepool
    {
        NSString *command = LBIString(request, @"command");
        NSString *args = LBIString(request, @"args");
        NSString *buildDir = LBIString(request, @"buildDir");
        NSString *sdkRoot = LBIString(request, @"sdkRoot");
        NSString *hostInputPath = LBIString(request, @"hostInputPath");
        NSString *hostProjectPath = LBIString(request, @"hostProjectPath");
        NSString *hostWorkDir = LBIString(request, @"hostWorkDir");
        NSMutableString *log = [NSMutableString stringWithFormat:@"Litter in-process Nyxian BuildKit\nrequest=%@\ncommand=%@\n", requestPath, command];

        if([command isEqualToString:@"litter-swift-check"])
        {
            NSString *source = hostInputPath.length > 0 ? hostInputPath : LBIWords(args).firstObject;
            if(source.length == 0) { return LBICopyResponse(64, @"missing-input", @"No Swift input was supplied.\n"); }
            NSArray<NSString *> *driverArgs = @[@"-typecheck", @"-sdk", sdkRoot, @"-target", @"arm64-apple-ios18.0", source];
            int code = LBIRunSwiftDriver(driverArgs, log);
            return LBICopyResponse(code, code == 0 ? @"swift-check-ok" : @"swift-check-failed", log);
        }

        if([command isEqualToString:@"litter-swift-build"] || [command isEqualToString:@"litter-swift-test"] || [command isEqualToString:@"litter-ipa-build"] || [command isEqualToString:@"litter-ipa-package"])
        {
            NSDictionary *manifest = LBIProjectManifest(hostProjectPath, log);
            if(manifest == nil) { return LBICopyResponse(66, @"project-invalid", log); }
            NSArray<NSString *> *sources = LBISwiftSources(manifest, hostWorkDir);
            if(sources.count == 0) { [log appendString:@"No Swift sources were staged for native compilation.\n"]; return LBICopyResponse(66, @"sources-missing", log); }
            NSString *deployment = LBIManifestString(manifest, @"deploymentTarget", @"18.0");
            NSString *productName = LBIManifestString(manifest, @"name", @"LitterApp");
            NSString *outDir = [hostWorkDir stringByAppendingPathComponent:@"BuildProducts"];
            NSString *appDir = [outDir stringByAppendingPathComponent:[productName stringByAppendingPathExtension:@"app"]];
            NSString *executable = [appDir stringByAppendingPathComponent:productName];
            [NSFileManager.defaultManager removeItemAtPath:appDir error:nil];
            [NSFileManager.defaultManager createDirectoryAtPath:appDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSMutableArray<NSString *> *driverArgs = [NSMutableArray arrayWithArray:@[@"-sdk", sdkRoot, @"-target", [@"arm64-apple-ios" stringByAppendingString:deployment], @"-o", executable]];
            [driverArgs addObjectsFromArray:sources];
            int code = LBIRunSwiftDriver(driverArgs, log);
            if(code != 0) { return LBICopyResponse(code, @"swift-build-failed", log); }
            chmod(executable.fileSystemRepresentation, 0755);
            [log appendFormat:@"Built app executable: %@\n", executable];
            LBIWriteInfoPlist(manifest, appDir, productName, deployment, log);
            LBICopyManifestResources(manifest, hostWorkDir, appDir, log);

            if([command isEqualToString:@"litter-ipa-build"] || [command isEqualToString:@"litter-ipa-package"])
            {
                NSString *artifactDir = [hostWorkDir stringByAppendingPathComponent:@"Artifacts"];
                NSString *ipaPath = [artifactDir stringByAppendingPathComponent:[productName stringByAppendingPathExtension:@"ipa"]];
                if(!LBIWriteStoredZip(appDir, productName, ipaPath, log))
                {
                    return LBICopyResponse(73, @"ipa-package-failed", log);
                }
                NSString *fakefsArtifactPath = [buildDir stringByAppendingPathComponent:ipaPath.lastPathComponent];
                [log appendFormat:@"Unsigned IPA artifact: %@\n", ipaPath];
                [log appendFormat:@"Fakefs artifact path: %@\n", fakefsArtifactPath];
                NSArray *artifacts = @[@{@"hostPath": ipaPath, @"fakefsPath": fakefsArtifactPath}];
                return LBICopyResponseWithArtifacts(0, @"ipa-build-ok", log, artifacts);
            }

            NSString *status = [command isEqualToString:@"litter-swift-test"] ? @"swift-test-ok" : @"swift-build-ok";
            return LBICopyResponse(0, status, log);
        }

        return NULL;
    }
}
