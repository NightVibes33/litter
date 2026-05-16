#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <MobileDevelopmentKit/MDKDriver.h>
#import <MobileDevelopmentKit/MDKJob.h>
#import <MobileDevelopmentKit/MDKDiagnostic.h>
#import <MobileDevelopmentKit/MDKLinker.h>

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
    NSMutableString *current = [NSMutableString string];
    unichar quote = 0;
    BOOL escaping = NO;
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;

    for(NSUInteger idx = 0; idx < raw.length; idx++)
    {
        unichar ch = [raw characterAtIndex:idx];
        if(escaping)
        {
            [current appendFormat:@"%C", ch];
            escaping = NO;
            continue;
        }
        if(ch == '\\' && quote != '\'')
        {
            escaping = YES;
            continue;
        }
        if(quote != 0)
        {
            if(ch == quote) { quote = 0; }
            else { [current appendFormat:@"%C", ch]; }
            continue;
        }
        if(ch == '\'' || ch == '"')
        {
            quote = ch;
            continue;
        }
        if([whitespace characterIsMember:ch])
        {
            if(current.length > 0)
            {
                [items addObject:[current copy]];
                [current setString:@""];
            }
            continue;
        }
        [current appendFormat:@"%C", ch];
    }

    if(escaping) { [current appendString:@"\\"]; }
    if(current.length > 0) { [items addObject:[current copy]]; }
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

static NSString *LBIJobTypeName(CCJobType type)
{
    switch(type)
    {
        case CCJobTypeCompiler: return @"compiler";
        case CCJobTypeSwiftCompiler: return @"swift-compiler";
        case CCJobTypeLinker: return @"linker";
        case CCJobTypeDriver: return @"driver";
        case CCJobTypeSwiftDriver: return @"swift-driver";
        case CCJobTypeUnknown: return @"unknown";
        default: return [NSString stringWithFormat:@"unknown-%u", type];
    }
}

static BOOL LBIExecuteJob(MDKJob *job, NSArray<MDKDiagnostic *> **diagnostics, NSString **mainSource)
{
    if(job.type == CCJobTypeLinker)
    {
        if(mainSource != nil) { *mainSource = nil; }
        return [MDKLinker executeJob:job outDiagnostics:diagnostics];
    }
    return [job executeJobWithOutDiagnostics:diagnostics withOutMainSource:mainSource];
}

static NSArray<NSString *> *LBINormalizedLinkerArguments(NSArray<NSString *> *arguments, BOOL *didNormalize)
{
    NSMutableArray<NSString *> *linkerArguments = [NSMutableArray array];
    BOOL normalized = NO;

    for(NSString *argument in arguments ?: @[])
    {
        if([argument hasPrefix:@"-fuse-ld="])
        {
            normalized = YES;
            continue;
        }

        if([argument isEqualToString:@"-Wl"] || [argument isEqualToString:@"-Xlinker"])
        {
            normalized = YES;
            continue;
        }

        if([argument hasPrefix:@"-Wl,"])
        {
            normalized = YES;
            NSString *payload = [argument substringFromIndex:4];
            for(NSString *part in [payload componentsSeparatedByString:@","])
            {
                if(part.length == 0 || [part isEqualToString:@"-Wl"]) { continue; }
                [linkerArguments addObject:part];
            }
        }
        else
        {
            [linkerArguments addObject:argument];
        }
    }

    if(didNormalize != nil) { *didNormalize = normalized; }
    return [linkerArguments copy];
}

static int LBIExecuteJobs(NSArray<MDKJob *> *jobs, NSMutableString *log, NSUInteger depth)
{
    if(depth > 8)
    {
        [log appendString:@"Nested driver expansion exceeded the safety limit.\n"];
        return 70;
    }

    int exitCode = 0;
    for(MDKJob *job in jobs)
    {
        NSArray<NSString *> *jobArguments = job.arguments ?: @[];

        BOOL didNormalizeLinkerArguments = NO;
        NSArray<NSString *> *normalizedLinkerArguments = LBINormalizedLinkerArguments(jobArguments, &didNormalizeLinkerArguments);
        if(didNormalizeLinkerArguments && job.type == CCJobTypeDriver)
        {
            [log appendFormat:@"job type=%@(%u) normalizing swift linker driver=yes\n", LBIJobTypeName(job.type), job.type];
            [log appendFormat:@"job args: %@\n", [jobArguments componentsJoinedByString:@" "]];
            [log appendFormat:@"linker args: %@\n", [normalizedLinkerArguments componentsJoinedByString:@" "]];

            NSArray<MDKDiagnostic *> *diagnostics = nil;
            NSString *mainSource = nil;
            MDKJob *linkerJob = [MDKJob jobWithType:CCJobTypeLinker withArguments:normalizedLinkerArguments];
            BOOL ok = LBIExecuteJob(linkerJob, &diagnostics, &mainSource);
            [log appendFormat:@"job type=linker(%u) source=%@ ok=%@\n", linkerJob.type, mainSource ?: @"", ok ? @"yes" : @"no"];
            if(diagnostics.count > 0) { [log appendString:LBIDiagnosticText(diagnostics)]; }
            if(!ok && exitCode == 0) { exitCode = 1; }
            continue;
        }

        if(job.type == CCJobTypeDriver)
        {
            [log appendFormat:@"job type=%@(%u) expanding=yes\n", LBIJobTypeName(job.type), job.type];
            [log appendFormat:@"job args: %@\n", [jobArguments componentsJoinedByString:@" "]];

            MDKDriver *driver = [MDKDriver driverWithArguments:jobArguments withType:CCDriverTypeClang];
            if(driver == nil)
            {
                [log appendString:@"Could not create Nyxian Clang driver for nested driver job.\n"];
                exitCode = exitCode == 0 ? 70 : exitCode;
                continue;
            }

            NSArray<MDKJob *> *nestedJobs = [driver generateJobs];
            if(nestedJobs.count == 0)
            {
                [log appendString:@"Nested Nyxian Clang driver produced no jobs.\n"];
                exitCode = exitCode == 0 ? 70 : exitCode;
                continue;
            }

            int nestedExitCode = LBIExecuteJobs(nestedJobs, log, depth + 1);
            [log appendFormat:@"job type=%@(%u) expanded ok=%@\n", LBIJobTypeName(job.type), job.type, nestedExitCode == 0 ? @"yes" : @"no"];
            if(nestedExitCode != 0) { exitCode = nestedExitCode; }
            continue;
        }

        if(job.type == CCJobTypeLinker && didNormalizeLinkerArguments)
        {
            [log appendFormat:@"job type=%@(%u) normalizing linker args=yes\n", LBIJobTypeName(job.type), job.type];
            [log appendFormat:@"job args: %@\n", [jobArguments componentsJoinedByString:@" "]];
            [log appendFormat:@"linker args: %@\n", [normalizedLinkerArguments componentsJoinedByString:@" "]];
            jobArguments = normalizedLinkerArguments;
            job = [MDKJob jobWithType:CCJobTypeLinker withArguments:normalizedLinkerArguments];
        }

        NSArray<MDKDiagnostic *> *diagnostics = nil;
        NSString *mainSource = nil;
        BOOL ok = LBIExecuteJob(job, &diagnostics, &mainSource);
        [log appendFormat:@"job type=%@(%u) source=%@ ok=%@\n", LBIJobTypeName(job.type), job.type, mainSource ?: @"", ok ? @"yes" : @"no"];
        [log appendFormat:@"job args: %@\n", [jobArguments componentsJoinedByString:@" "]];
        if(diagnostics.count > 0) { [log appendString:LBIDiagnosticText(diagnostics)]; }
        if(!ok && exitCode == 0) { exitCode = 1; }
    }
    return exitCode;
}

static NSString *LBIOutputPath(NSArray<NSString *> *words, NSString *fallbackName)
{
    for(NSUInteger idx = 0; idx + 1 < words.count; idx++)
    {
        if([words[idx] isEqualToString:@"-o"]) { return words[idx + 1]; }
    }
    return fallbackName;
}

static BOOL LBIFlagTakesValue(NSString *word)
{
    static NSSet<NSString *> *valueFlags;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        valueFlags = [NSSet setWithArray:@[
            @"-D", @"-I", @"-F", @"-L", @"-l", @"-framework",
            @"-include", @"-isystem", @"-iquote", @"-idirafter",
            @"-isysroot", @"--sysroot", @"-target", @"-arch", @"-x",
            @"-std", @"-stdlib", @"-mllvm",
            @"-module-name", @"-package-name", @"-emit-module-path",
            @"-emit-dependencies-path", @"-emit-reference-dependencies-path",
            @"-Xcc", @"-Xlinker", @"-Xfrontend"
        ]];
    });
    return [valueFlags containsObject:word];
}

static BOOL LBIWordsContain(NSArray<NSString *> *words, NSString *value);

static BOOL LBIIsInputWithExtensions(NSString *word, NSSet<NSString *> *extensions)
{
    if(word.length == 0 || [word hasPrefix:@"-"]) { return NO; }
    NSString *ext = word.pathExtension.lowercaseString;
    return ext.length > 0 && [extensions containsObject:ext];
}

static NSString *LBIFirstInputWithExtensions(NSArray<NSString *> *words, NSSet<NSString *> *extensions)
{
    BOOL skipNext = NO;
    for(NSString *word in words)
    {
        if(skipNext) { skipNext = NO; continue; }
        if(LBIFlagTakesValue(word) || [word isEqualToString:@"-o"])
        {
            skipNext = YES;
            continue;
        }
        if(LBIIsInputWithExtensions(word, extensions)) { return word; }
    }
    return nil;
}

static NSArray<NSString *> *LBIClangUserFlags(NSArray<NSString *> *words, NSSet<NSString *> *inputExtensions)
{
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    BOOL skipNext = NO;
    BOOL preserveNext = NO;
    for(NSUInteger idx = 0; idx < words.count; idx++)
    {
        NSString *word = words[idx];
        if(skipNext) { skipNext = NO; continue; }
        if([word isEqualToString:@"-o"] || [word isEqualToString:@"-isysroot"] || [word isEqualToString:@"--sysroot"] || [word isEqualToString:@"-target"] || [word isEqualToString:@"-arch"])
        {
            skipNext = YES;
            preserveNext = NO;
            continue;
        }
        if(preserveNext)
        {
            [flags addObject:word];
            preserveNext = NO;
            continue;
        }
        if(LBIIsInputWithExtensions(word, inputExtensions)) { continue; }
        if([word hasPrefix:@"-isysroot"] || [word hasPrefix:@"--sysroot="] || [word hasPrefix:@"-target="] || [word hasPrefix:@"-arch"]) { continue; }
        if([word hasPrefix:@"-"])
        {
            [flags addObject:word];
            preserveNext = LBIFlagTakesValue(word);
        }
    }
    return flags;
}

static NSString *LBIClangFallbackOutput(NSString *source, NSArray<NSString *> *words)
{
    NSString *base = source.lastPathComponent.stringByDeletingPathExtension;
    if(base.length == 0) { base = @"a"; }
    if(LBIWordsContain(words, @"-c")) { return [base stringByAppendingPathExtension:@"o"]; }
    if(LBIWordsContain(words, @"-S")) { return [base stringByAppendingPathExtension:@"s"]; }
    if(LBIWordsContain(words, @"-E")) { return [base stringByAppendingPathExtension:@"i"]; }
    return @"a.out";
}

static NSString *LBIFakefsOutputPath(NSString *requestedOutput, NSString *cwd)
{
    if([requestedOutput hasPrefix:@"/"]) { return requestedOutput; }
    return [(cwd.length > 0 ? cwd : @"/root") stringByAppendingPathComponent:requestedOutput];
}

static int LBIRunClangDriver(NSArray<NSString *> *arguments, NSMutableString *log)
{
    [log appendFormat:@"clang driver args: %@\n", [arguments componentsJoinedByString:@" "]];
    MDKDriver *driver = [MDKDriver driverWithArguments:arguments withType:CCDriverTypeClang];
    if(driver == nil)
    {
        [log appendString:@"Could not create Nyxian Clang driver.\n"];
        return 70;
    }
    NSArray<MDKJob *> *jobs = [driver generateJobs];
    if(jobs.count == 0)
    {
        [log appendString:@"Nyxian Clang driver produced no jobs.\n"];
        return 70;
    }
    return LBIExecuteJobs(jobs, log, 0);
}

static NSArray<NSString *> *LBISwiftcUserFlags(NSArray<NSString *> *words)
{
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    BOOL skipNext = NO;
    BOOL preserveNext = NO;
    for(NSUInteger idx = 0; idx < words.count; idx++)
    {
        NSString *word = words[idx];
        if(skipNext) { skipNext = NO; continue; }
        if([word isEqualToString:@"-o"] || [word isEqualToString:@"-sdk"] || [word isEqualToString:@"-target"])
        {
            skipNext = YES;
            preserveNext = NO;
            continue;
        }
        if(preserveNext)
        {
            [flags addObject:word];
            preserveNext = NO;
            continue;
        }
        if([word hasSuffix:@".swift"]) { continue; }
        if([word hasPrefix:@"-"])
        {
            [flags addObject:word];
            preserveNext = LBIFlagTakesValue(word);
        }
    }
    return flags;
}

static BOOL LBIWordsContain(NSArray<NSString *> *words, NSString *value)
{
    for(NSString *word in words) { if([word isEqualToString:value]) { return YES; } }
    return NO;
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
    return LBIExecuteJobs(jobs, log, 0);
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

static void LBIAppendSwiftSource(NSMutableArray<NSString *> *sources, NSString *path)
{
    if(path.length == 0 || ![path.pathExtension.lowercaseString isEqualToString:@"swift"]) { return; }
    BOOL isDirectory = NO;
    if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) { return; }
    if(![sources containsObject:path]) { [sources addObject:path]; }
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
                LBIAppendSwiftSource(sources, [hostRoot stringByAppendingPathComponent:relative]);
            }
        }
        LBIAppendSwiftSource(sources, hostRoot);
    }

    NSString *entrypoint = [manifest[@"entrypoint"] isKindOfClass:NSString.class] ? manifest[@"entrypoint"] : @"";
    if(entrypoint.length > 0)
    {
        NSString *hostEntrypoint = [entrypoint hasPrefix:@"/"] ? entrypoint : [hostWorkDir stringByAppendingPathComponent:entrypoint];
        LBIAppendSwiftSource(sources, hostEntrypoint);
    }
    return sources;
}


static NSString *LBIManifestString(NSDictionary *manifest, NSString *key, NSString *fallback)
{
    id value = manifest[key];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : fallback;
}

static NSString *LBIIpaArtifactName(NSDictionary *manifest, NSString *productName)
{
    NSString *output = LBIManifestString(manifest, @"output", @"");
    NSString *name = output.length > 0 ? output.lastPathComponent : @"";
    if(name.length == 0) { name = [productName stringByAppendingPathExtension:@"ipa"]; }
    if(name.pathExtension.length == 0) { name = [name stringByAppendingPathExtension:@"ipa"]; }
    return name;
}

static NSString *LBIFakefsProjectDirectory(NSDictionary *request, NSString *cwd)
{
    NSString *fakefsProjectPath = LBIString(request, @"fakefsProjectPath");
    if(fakefsProjectPath.length > 0) { return fakefsProjectPath.stringByDeletingLastPathComponent; }
    return cwd.length > 0 ? cwd : @"/root";
}

static NSString *LBIFakefsIPAOutputPath(NSDictionary *manifest, NSDictionary *request, NSString *cwd, NSString *buildDir, NSString *artifactName)
{
    NSString *output = LBIManifestString(manifest, @"output", @"");
    if(output.length == 0) { return [buildDir stringByAppendingPathComponent:artifactName]; }
    if([output hasPrefix:@"/"]) { return output; }
    return [LBIFakefsProjectDirectory(request, cwd) stringByAppendingPathComponent:output];
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
        NSString *fakefsBuildDir = LBIString(request, @"fakefsBuildDir");
        if(fakefsBuildDir.length == 0) { fakefsBuildDir = buildDir; }
        NSString *cwd = LBIString(request, @"cwd");
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


        if([command isEqualToString:@"litter-swiftc"])
        {
            NSArray<NSString *> *words = LBIWords(args);
            NSString *source = hostInputPath.length > 0 ? hostInputPath : nil;
            if(source.length == 0)
            {
                for(NSString *word in words)
                {
                    if([word hasSuffix:@".swift"]) { source = word; break; }
                }
            }
            if(source.length == 0) { return LBICopyResponse(64, @"missing-input", @"No Swift input was supplied.\n"); }

            if(LBIWordsContain(words, @"-typecheck") || LBIWordsContain(words, @"-parse"))
            {
                NSArray<NSString *> *driverArgs = @[@"-typecheck", @"-sdk", sdkRoot, @"-target", @"arm64-apple-ios18.0", source];
                int code = LBIRunSwiftDriver(driverArgs, log);
                return LBICopyResponse(code, code == 0 ? @"swiftc-check-ok" : @"swiftc-check-failed", log);
            }

            NSString *fallbackOutput = source.lastPathComponent.stringByDeletingPathExtension;
            if(fallbackOutput.length == 0) { fallbackOutput = @"main"; }
            NSString *requestedOutput = LBIOutputPath(words, fallbackOutput);
            NSString *artifactDir = [hostWorkDir stringByAppendingPathComponent:@"Artifacts"];
            [NSFileManager.defaultManager createDirectoryAtPath:artifactDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *hostOutput = [artifactDir stringByAppendingPathComponent:requestedOutput.lastPathComponent];
            NSMutableArray<NSString *> *driverArgs = [NSMutableArray array];
            [driverArgs addObjectsFromArray:LBISwiftcUserFlags(words)];
            [driverArgs addObjectsFromArray:@[@"-sdk", sdkRoot, @"-target", @"arm64-apple-ios18.0", @"-o", hostOutput, source]];
            int code = LBIRunSwiftDriver(driverArgs, log);
            if(code != 0) { return LBICopyResponse(code, @"swiftc-failed", log); }
            chmod(hostOutput.fileSystemRepresentation, 0755);
            NSString *fakefsPath = [requestedOutput hasPrefix:@"/"] ? requestedOutput : [cwd stringByAppendingPathComponent:requestedOutput];
            [log appendFormat:@"Swift compiler output: %@\n", hostOutput];
            [log appendFormat:@"Fakefs output path: %@\n", fakefsPath];
            NSArray *artifacts = @[@{@"hostPath": hostOutput, @"fakefsPath": fakefsPath}];
            return LBICopyResponseWithArtifacts(0, @"swiftc-ok", log, artifacts);
        }


        if([command isEqualToString:@"litter-clang"])
        {
            NSArray<NSString *> *words = LBIWords(args);
            NSSet<NSString *> *sourceExtensions = [NSSet setWithArray:@[@"c", @"cc", @"cpp", @"cxx", @"m", @"mm"]];
            NSString *source = hostInputPath.length > 0 ? hostInputPath : LBIFirstInputWithExtensions(words, sourceExtensions);
            if(source.length == 0) { return LBICopyResponse(64, @"clang-missing-input", @"No C, C++, Objective-C, or Objective-C++ input was supplied.\n"); }

            NSString *requestedOutput = LBIOutputPath(words, LBIClangFallbackOutput(source, words));
            NSString *artifactDir = [hostWorkDir stringByAppendingPathComponent:@"Artifacts"];
            [NSFileManager.defaultManager createDirectoryAtPath:artifactDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *hostOutput = [artifactDir stringByAppendingPathComponent:requestedOutput.lastPathComponent];
            NSMutableArray<NSString *> *driverArgs = [NSMutableArray array];
            [driverArgs addObjectsFromArray:LBIClangUserFlags(words, sourceExtensions)];
            [driverArgs addObjectsFromArray:@[@"-isysroot", sdkRoot, @"-target", @"arm64-apple-ios18.0", @"-miphoneos-version-min=18.0", @"-o", hostOutput, source]];
            int code = LBIRunClangDriver(driverArgs, log);
            if(code != 0) { return LBICopyResponse(code, @"clang-failed", log); }
            if(![NSFileManager.defaultManager fileExistsAtPath:hostOutput])
            {
                [log appendFormat:@"Clang completed without producing an artifact at %@.\n", hostOutput];
                return LBICopyResponse(0, @"clang-ok", log);
            }
            chmod(hostOutput.fileSystemRepresentation, 0755);
            NSString *fakefsPath = LBIFakefsOutputPath(requestedOutput, cwd);
            [log appendFormat:@"Clang output: %@\n", hostOutput];
            [log appendFormat:@"Fakefs output path: %@\n", fakefsPath];
            NSArray *artifacts = @[@{@"hostPath": hostOutput, @"fakefsPath": fakefsPath}];
            return LBICopyResponseWithArtifacts(0, @"clang-ok", log, artifacts);
        }

        if([command isEqualToString:@"litter-ld"])
        {
            NSArray<NSString *> *words = LBIWords(args);
            NSSet<NSString *> *inputExtensions = [NSSet setWithArray:@[@"o", @"a", @"dylib", @"tbd"]];
            NSString *input = hostInputPath.length > 0 ? hostInputPath : LBIFirstInputWithExtensions(words, inputExtensions);
            if(input.length == 0) { return LBICopyResponse(64, @"ld-missing-input", @"No object, archive, dylib, or tbd input was supplied.\n"); }

            NSString *requestedOutput = LBIOutputPath(words, @"a.out");
            NSString *artifactDir = [hostWorkDir stringByAppendingPathComponent:@"Artifacts"];
            [NSFileManager.defaultManager createDirectoryAtPath:artifactDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *hostOutput = [artifactDir stringByAppendingPathComponent:requestedOutput.lastPathComponent];
            NSMutableArray<NSString *> *driverArgs = [NSMutableArray array];
            [driverArgs addObjectsFromArray:LBIClangUserFlags(words, inputExtensions)];
            [driverArgs addObjectsFromArray:@[@"-isysroot", sdkRoot, @"-target", @"arm64-apple-ios18.0", @"-miphoneos-version-min=18.0", @"-o", hostOutput, input]];
            int code = LBIRunClangDriver(driverArgs, log);
            if(code != 0) { return LBICopyResponse(code, @"ld-failed", log); }
            if(![NSFileManager.defaultManager fileExistsAtPath:hostOutput])
            {
                [log appendFormat:@"Link completed without producing an artifact at %@.\n", hostOutput];
                return LBICopyResponse(0, @"ld-ok", log);
            }
            chmod(hostOutput.fileSystemRepresentation, 0755);
            NSString *fakefsPath = LBIFakefsOutputPath(requestedOutput, cwd);
            [log appendFormat:@"Linker output: %@\n", hostOutput];
            [log appendFormat:@"Fakefs output path: %@\n", fakefsPath];
            NSArray *artifacts = @[@{@"hostPath": hostOutput, @"fakefsPath": fakefsPath}];
            return LBICopyResponseWithArtifacts(0, @"ld-ok", log, artifacts);
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
                NSString *artifactName = LBIIpaArtifactName(manifest, productName);
                NSString *ipaPath = [artifactDir stringByAppendingPathComponent:artifactName];
                if(!LBIWriteStoredZip(appDir, productName, ipaPath, log))
                {
                    return LBICopyResponse(73, @"ipa-package-failed", log);
                }
                NSString *fakefsArtifactPath = LBIFakefsIPAOutputPath(manifest, request, cwd, fakefsBuildDir, ipaPath.lastPathComponent);
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
