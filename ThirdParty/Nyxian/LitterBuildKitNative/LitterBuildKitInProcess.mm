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

#ifdef LBN_ENABLE_KITTYSTORE_SIGNER
#include "common/archive.h"
#include "bundle.h"
#include "openssl.h"
#endif

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
    BOOL rewriteSysrootValue = NO;

    for(NSString *argument in arguments ?: @[])
    {
        if(rewriteSysrootValue)
        {
            [linkerArguments addObject:argument];
            rewriteSysrootValue = NO;
            continue;
        }

        if([argument hasPrefix:@"-fuse-ld="])
        {
            normalized = YES;
            continue;
        }

        if([argument isEqualToString:@"-isysroot"] || [argument isEqualToString:@"--sysroot"])
        {
            normalized = YES;
            [linkerArguments addObject:@"-syslibroot"];
            rewriteSysrootValue = YES;
            continue;
        }

        if([argument hasPrefix:@"--sysroot="])
        {
            normalized = YES;
            [linkerArguments addObject:@"-syslibroot"];
            [linkerArguments addObject:[argument substringFromIndex:10]];
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
            BOOL rewritePayloadSysrootValue = NO;
            for(NSString *part in [payload componentsSeparatedByString:@","])
            {
                if(part.length == 0 || [part isEqualToString:@"-Wl"]) { continue; }
                if(rewritePayloadSysrootValue)
                {
                    [linkerArguments addObject:part];
                    rewritePayloadSysrootValue = NO;
                    continue;
                }
                if([part isEqualToString:@"-isysroot"] || [part isEqualToString:@"--sysroot"])
                {
                    [linkerArguments addObject:@"-syslibroot"];
                    rewritePayloadSysrootValue = YES;
                    continue;
                }
                if([part hasPrefix:@"--sysroot="])
                {
                    [linkerArguments addObject:@"-syslibroot"];
                    [linkerArguments addObject:[part substringFromIndex:10]];
                    continue;
                }
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
            if(!ok)
            {
                if(exitCode == 0) { exitCode = 1; }
                break;
            }
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

        MDKJob *jobToExecute = job;
        NSArray<NSString *> *argumentsToExecute = jobArguments;
        if(job.type == CCJobTypeLinker && didNormalizeLinkerArguments)
        {
            [log appendFormat:@"job type=%@(%u) normalizing linker args=yes\n", LBIJobTypeName(job.type), job.type];
            [log appendFormat:@"job args: %@\n", [jobArguments componentsJoinedByString:@" "]];
            [log appendFormat:@"linker args: %@\n", [normalizedLinkerArguments componentsJoinedByString:@" "]];
            argumentsToExecute = normalizedLinkerArguments;
            jobToExecute = [MDKJob jobWithType:CCJobTypeLinker withArguments:normalizedLinkerArguments];
        }

        NSArray<MDKDiagnostic *> *diagnostics = nil;
        NSString *mainSource = nil;
        BOOL ok = LBIExecuteJob(jobToExecute, &diagnostics, &mainSource);
        [log appendFormat:@"job type=%@(%u) source=%@ ok=%@\n", LBIJobTypeName(jobToExecute.type), jobToExecute.type, mainSource ?: @"", ok ? @"yes" : @"no"];
        [log appendFormat:@"job args: %@\n", [argumentsToExecute componentsJoinedByString:@" "]];
        if(diagnostics.count > 0) { [log appendString:LBIDiagnosticText(diagnostics)]; }
        if(!ok)
        {
            if(exitCode == 0) { exitCode = 1; }
            break;
        }
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
            @"-std", @"-stdlib", @"-mllvm", @"-resource-dir",
            @"-module-name", @"-package-name", @"-emit-module-path",
            @"-emit-dependencies-path", @"-emit-reference-dependencies-path",
            @"-Xcc", @"-Xlinker", @"-Xfrontend"
        ]];
    });
    return [valueFlags containsObject:word];
}

static BOOL LBIWordsContain(NSArray<NSString *> *words, NSString *value);

static void LBIAppendSwiftSDKCompatibilityFlags(NSMutableArray<NSString *> *arguments)
{
    if([arguments containsObject:@"-disable-sdk-module-interface-validation"]) { return; }
    [arguments addObject:@"-Xfrontend"];
    [arguments addObject:@"-disable-sdk-module-interface-validation"];
}

static BOOL LBIArgumentsContainResourceDir(NSArray<NSString *> *arguments)
{
    for(NSUInteger idx = 0; idx < arguments.count; idx++)
    {
        NSString *argument = arguments[idx];
        if([argument isEqualToString:@"-resource-dir"] || [argument hasPrefix:@"-resource-dir="]) { return YES; }
        if([argument isEqualToString:@"-Xcc"] && idx + 1 < arguments.count)
        {
            NSString *next = arguments[idx + 1];
            if([next isEqualToString:@"-resource-dir"] || [next hasPrefix:@"-resource-dir="]) { return YES; }
        }
    }
    return NO;
}

static BOOL LBIArgumentsContainSwiftResourceDir(NSArray<NSString *> *arguments)
{
    NSArray<NSString *> *words = arguments ?: @[];
    for(NSUInteger idx = 0; idx < words.count; idx++)
    {
        NSString *argument = words[idx];
        if([argument isEqualToString:@"-Xcc"])
        {
            idx++;
            continue;
        }
        if([argument isEqualToString:@"-resource-dir"] || [argument hasPrefix:@"-resource-dir="]) { return YES; }
    }
    return NO;
}

static BOOL LBIArgumentsContainSwiftClangResourceDir(NSArray<NSString *> *arguments)
{
    for(NSUInteger idx = 0; idx + 1 < arguments.count; idx++)
    {
        NSString *argument = arguments[idx];
        if(![argument isEqualToString:@"-Xcc"]) { continue; }
        NSString *next = arguments[idx + 1];
        if([next isEqualToString:@"-resource-dir"] || [next hasPrefix:@"-resource-dir="]) { return YES; }
    }
    return NO;
}

static BOOL LBIHeaderExists(NSString *root, NSString *relative)
{
    if(root.length == 0) { return NO; }
    return [NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:relative]];
}

static void LBIAppendClangResourceDir(NSMutableArray<NSString *> *arguments, NSString *resourceDir, NSMutableString *log)
{
    if(resourceDir.length == 0)
    {
        [log appendString:@"warning: request did not include clangResourceDir; UIKit/Foundation C-family imports may fail.\n"];
        return;
    }
    if(!LBIHeaderExists(resourceDir, @"include/stdarg.h"))
    {
        [log appendFormat:@"warning: clang resource dir is missing include/stdarg.h: %@\n", resourceDir];
    }
    if(LBIArgumentsContainResourceDir(arguments)) { return; }
    [arguments addObject:@"-resource-dir"];
    [arguments addObject:resourceDir];
}

static void LBIAppendSwiftClangResourceDir(NSMutableArray<NSString *> *arguments, NSString *resourceDir, NSMutableString *log)
{
    if(resourceDir.length == 0)
    {
        [log appendString:@"warning: request did not include clangResourceDir; Swift SDK module imports may fail.\n"];
        return;
    }
    if(!LBIHeaderExists(resourceDir, @"include/stdarg.h"))
    {
        [log appendFormat:@"warning: clang resource dir is missing include/stdarg.h: %@\n", resourceDir];
    }
    if(LBIArgumentsContainSwiftClangResourceDir(arguments)) { return; }
    [arguments addObject:@"-Xcc"];
    [arguments addObject:@"-resource-dir"];
    [arguments addObject:@"-Xcc"];
    [arguments addObject:resourceDir];
}

static NSString *LBIFirstUsableSwiftResourceDir(NSArray<NSString *> *candidates, NSMutableString *log)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    for(NSString *candidate in candidates ?: @[])
    {
        if(candidate.length == 0) { continue; }
        BOOL isDirectory = NO;
        if(![fm fileExistsAtPath:candidate isDirectory:&isDirectory] || !isDirectory) { continue; }
        NSString *iphoneOSDir = [candidate stringByAppendingPathComponent:@"iphoneos"];
        BOOL iphoneOSIsDirectory = NO;
        if([fm fileExistsAtPath:iphoneOSDir isDirectory:&iphoneOSIsDirectory] && iphoneOSIsDirectory)
        {
            return candidate;
        }
        [log appendFormat:@"warning: Swift resource dir candidate is missing iphoneos target directory: %@\n", candidate];
    }
    return nil;
}

static NSString *LBIResolvedSwiftResourceDir(NSString *swiftResourceDir, NSString *toolchainRoot, NSString *buildKitRoot, NSString *sdkRoot, NSMutableString *log)
{
    (void)sdkRoot;
    NSString *documentsRoot = buildKitRoot.length > 0 ? buildKitRoot.stringByDeletingLastPathComponent : @"";
    return LBIFirstUsableSwiftResourceDir(@[
        swiftResourceDir ?: @"",
        toolchainRoot.length > 0 ? [toolchainRoot stringByAppendingPathComponent:@"SwiftResourceDir"] : @"",
        buildKitRoot.length > 0 ? [buildKitRoot stringByAppendingPathComponent:@"Toolchains/Nyxian/SwiftResourceDir"] : @"",
        documentsRoot.length > 0 ? [documentsRoot stringByAppendingPathComponent:@"Developer/usr/lib/swift"] : @""
    ], log);
}

static BOOL LBIAppendSwiftResourceDir(NSMutableArray<NSString *> *arguments,
                                      NSString *swiftResourceDir,
                                      NSString *toolchainRoot,
                                      NSString *buildKitRoot,
                                      NSString *sdkRoot,
                                      NSMutableString *log)
{
    if(LBIArgumentsContainSwiftResourceDir(arguments)) { return YES; }
    NSString *resourceDir = LBIResolvedSwiftResourceDir(swiftResourceDir, toolchainRoot, buildKitRoot, sdkRoot, log);
    if(resourceDir.length == 0)
    {
        [log appendString:@"error: no usable Swift resource directory was found. Expected BuildKit manifest toolchain.swiftResourceDir to contain an iphoneos target directory.\n"];
        return NO;
    }
    [log appendFormat:@"Swift resource dir: %@\n", resourceDir];
    [arguments addObject:@"-resource-dir"];
    [arguments addObject:resourceDir];
    return YES;
}

static BOOL LBISourceIsCXX(NSString *source)
{
    NSString *ext = source.pathExtension.lowercaseString;
    return [ext isEqualToString:@"cc"] || [ext isEqualToString:@"cpp"] || [ext isEqualToString:@"cxx"] || [ext isEqualToString:@"mm"];
}

static void LBIAppendCXXStandardLibraryHeaders(NSMutableArray<NSString *> *arguments, NSString *includeDir, NSString *source, NSMutableString *log)
{
    if(!LBISourceIsCXX(source) || [arguments containsObject:@"-nostdinc++"]) { return; }
    if(includeDir.length == 0)
    {
        [log appendString:@"warning: request did not include cxxStandardLibraryIncludeDir; C++ standard library imports may fail.\n"];
        return;
    }
    if(!LBIHeaderExists(includeDir, @"vector"))
    {
        [log appendFormat:@"warning: libc++ include dir is missing vector: %@\n", includeDir];
    }
    [arguments addObject:@"-stdlib=libc++"];
    [arguments addObject:@"-isystem"];
    [arguments addObject:includeDir];
}

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
        if([word isEqualToString:@"-o"] || [word isEqualToString:@"-isysroot"] || [word isEqualToString:@"--sysroot"] || [word isEqualToString:@"-target"] || [word isEqualToString:@"-arch"] || [word isEqualToString:@"-resource-dir"])
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
        if([word hasPrefix:@"-isysroot"] || [word hasPrefix:@"--sysroot="] || [word hasPrefix:@"-target="] || [word hasPrefix:@"-arch"] || [word hasPrefix:@"-resource-dir="]) { continue; }
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


#ifdef LBN_ENABLE_KITTYSTORE_SIGNER
static NSDictionary *LBIJSONDictionaryFromFile(NSString *path, NSMutableString *log)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if(data.length == 0)
    {
        [log appendFormat:@"Signing plan is missing or empty: %@\n", path ?: @""];
        return nil;
    }
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if(![object isKindOfClass:NSDictionary.class])
    {
        [log appendFormat:@"Signing plan is not a JSON object: %@\n", error.localizedDescription ?: @"unknown decode error"];
        return nil;
    }
    return object;
}

static NSDictionary *LBIDictionaryValue(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSString *LBINestedString(NSDictionary *dictionary, NSString *section, NSString *key)
{
    return LBIString(LBIDictionaryValue(dictionary, section), key);
}

static BOOL LBIBoolValue(id value)
{
    if([value isKindOfClass:NSNumber.class]) { return [value boolValue]; }
    if([value isKindOfClass:NSString.class])
    {
        NSString *lower = [(NSString *)value lowercaseString];
        return [lower isEqualToString:@"true"] || [lower isEqualToString:@"yes"] || [lower isEqualToString:@"1"];
    }
    return NO;
}

static BOOL LBINestedBool(NSDictionary *dictionary, NSString *section, NSString *key)
{
    return LBIBoolValue(LBIDictionaryValue(dictionary, section)[key]);
}

static NSArray<NSString *> *LBIStringArray(NSDictionary *dictionary, NSString *section, NSString *key)
{
    id value = LBIDictionaryValue(dictionary, section)[key];
    if(![value isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for(id item in (NSArray *)value)
    {
        if([item isKindOfClass:NSString.class] && [(NSString *)item length] > 0) { [result addObject:item]; }
    }
    return result;
}

static NSString *LBISafeFileComponent(NSString *raw, NSString *fallback)
{
    NSString *value = raw.length > 0 ? raw : fallback;
    NSMutableString *safe = [NSMutableString stringWithCapacity:value.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    for(NSUInteger idx = 0; idx < value.length; idx++)
    {
        unichar ch = [value characterAtIndex:idx];
        [safe appendFormat:@"%C", [allowed characterIsMember:ch] ? ch : '-'];
    }
    while([safe hasPrefix:@"."] || [safe hasPrefix:@"-"]) { [safe deleteCharactersInRange:NSMakeRange(0, 1)]; }
    return safe.length > 0 ? safe : fallback;
}

static NSString *LBIKittyStoreFindApp(NSString *workRoot)
{
    NSString *payload = [workRoot stringByAppendingPathComponent:@"Payload"];
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:payload error:nil] ?: @[];
    for(NSString *item in items)
    {
        if([item.pathExtension.lowercaseString isEqualToString:@"app"])
        {
            return [payload stringByAppendingPathComponent:item];
        }
    }
    return @"";
}

static NSString *LBIKittyStoreCertificatePath(NSString *hostWorkDir, NSMutableString *log)
{
    NSData *certificate = [NSUserDefaults.standardUserDefaults dataForKey:@"LCCertificateData"];
    if(certificate.length == 0)
    {
        [log appendString:@"No saved LCCertificateData was found in app settings. Import and validate a .p12 first.\n"];
        return @"";
    }
    NSString *inputDir = [hostWorkDir stringByAppendingPathComponent:@"Inputs"];
    [NSFileManager.defaultManager createDirectoryAtPath:inputDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [inputDir stringByAppendingPathComponent:@"KittyStoreSigningCertificate.p12"];
    if(![certificate writeToFile:path atomically:YES])
    {
        [log appendFormat:@"Could not write staged certificate to %@\n", path];
        return @"";
    }
    return path;
}

static NSString *LBIKittyStoreProvisionPath(NSDictionary *plan, NSString *appDir, NSMutableString *log)
{
    NSString *profile = LBINestedString(plan, @"signing", @"provisioningProfile");
    if(profile.length > 0 && ![profile isEqualToString:@"embedded"] && [NSFileManager.defaultManager fileExistsAtPath:profile])
    {
        return profile;
    }
    NSString *embedded = [appDir stringByAppendingPathComponent:@"embedded.mobileprovision"];
    if([NSFileManager.defaultManager fileExistsAtPath:embedded]) { return embedded; }
    [log appendFormat:@"Provisioning profile is missing. Plan profile=%@, embedded=%@\n", profile ?: @"", embedded];
    return @"";
}

static NSString *LBIKittyStoreWriteEntitlements(NSDictionary *plan, NSString *hostWorkDir, NSMutableString *log)
{
    id raw = LBIDictionaryValue(plan, @"modify")[@"entitlements"];
    id plistObject = nil;
    NSData *plistData = nil;
    if([raw isKindOfClass:NSDictionary.class])
    {
        plistObject = raw;
    }
    else if([raw isKindOfClass:NSString.class])
    {
        NSString *text = [(NSString *)raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(text.length == 0 || [text isEqualToString:@"{}"] || [text isEqualToString:@"{ }"]) { return @""; }
        if([text hasPrefix:@"<"])
        {
            plistData = [text dataUsingEncoding:NSUTF8StringEncoding];
        }
        else if([text hasPrefix:@"{"])
        {
            NSData *jsonData = [text dataUsingEncoding:NSUTF8StringEncoding];
            plistObject = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
        }
    }
    if(plistData.length == 0 && plistObject != nil)
    {
        if([plistObject isKindOfClass:NSDictionary.class] && [(NSDictionary *)plistObject count] == 0) { return @""; }
        plistData = [NSPropertyListSerialization dataWithPropertyList:plistObject format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    }
    if(plistData.length == 0) { return @""; }
    NSString *inputDir = [hostWorkDir stringByAppendingPathComponent:@"Inputs"];
    [NSFileManager.defaultManager createDirectoryAtPath:inputDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [inputDir stringByAppendingPathComponent:@"KittyStoreEntitlements.plist"];
    if(![plistData writeToFile:path atomically:YES])
    {
        [log appendString:@"Could not write custom entitlements plist; provisioning profile entitlements will be used.\n"];
        return @"";
    }
    [log appendFormat:@"Using custom entitlements: %@\n", path];
    return path;
}

static void LBIKittyStoreModifyInfoPlist(NSDictionary *plan, NSString *appDir, NSMutableString *log)
{
    NSString *infoPath = [appDir stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if(info.count == 0)
    {
        [log appendFormat:@"Could not read Info.plist at %@\n", infoPath];
        return;
    }
    NSString *displayName = LBINestedString(plan, @"app", @"name");
    NSString *bundleID = LBINestedString(plan, @"app", @"bundleIdentifier");
    NSString *version = LBINestedString(plan, @"app", @"version");
    if(displayName.length > 0)
    {
        info[@"CFBundleDisplayName"] = displayName;
        info[@"CFBundleName"] = displayName;
    }
    if(bundleID.length > 0) { info[@"CFBundleIdentifier"] = bundleID; }
    if(version.length > 0)
    {
        info[@"CFBundleShortVersionString"] = version;
        info[@"CFBundleVersion"] = version;
    }
    NSDictionary *properties = LBIDictionaryValue(plan, @"properties");
    if(LBIBoolValue(properties[@"fileSharing"])) { info[@"UISupportsDocumentBrowser"] = @YES; }
    if(LBIBoolValue(properties[@"iTunesFileSharing"])) { info[@"UIFileSharingEnabled"] = @YES; }
    if(LBIBoolValue(properties[@"proMotion"])) { info[@"CADisableMinimumFrameDurationOnPhone"] = @NO; }
    if(LBIBoolValue(properties[@"gameMode"])) { info[@"GCSupportsGameMode"] = @YES; }
    if(LBIBoolValue(properties[@"iPadFullscreen"])) { info[@"UIRequiresFullScreen"] = @YES; }
    if(LBIBoolValue(properties[@"removeURLScheme"])) { [info removeObjectForKey:@"CFBundleURLTypes"]; }
    if([info writeToFile:infoPath atomically:YES])
    {
        [log appendString:@"Applied KittyStore Info.plist property changes.\n"];
    }
    else
    {
        [log appendFormat:@"Could not write Info.plist at %@\n", infoPath];
    }
}

static BOOL LBICopyIntoAppSubdir(NSString *source, NSString *appDir, NSString *subdir, NSMutableString *log)
{
    if(source.length == 0) { return NO; }
    BOOL isDir = NO;
    if(![NSFileManager.defaultManager fileExistsAtPath:source isDirectory:&isDir])
    {
        [log appendFormat:@"KittyStore input missing: %@\n", source];
        return NO;
    }
    NSString *destDir = [appDir stringByAppendingPathComponent:subdir];
    [NSFileManager.defaultManager createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *dest = [destDir stringByAppendingPathComponent:source.lastPathComponent];
    [NSFileManager.defaultManager removeItemAtPath:dest error:nil];
    NSError *error = nil;
    if(![NSFileManager.defaultManager copyItemAtPath:source toPath:dest error:&error])
    {
        [log appendFormat:@"Could not copy %@ into %@: %@\n", source.lastPathComponent, subdir, error.localizedDescription ?: @"unknown error"];
        return NO;
    }
    [log appendFormat:@"Copied %@ into %@.\n", source.lastPathComponent, subdir];
    return YES;
}

static void LBIKittyStoreCollectInputs(NSDictionary *plan, NSString *appDir, vector<string> &dylibs, NSMutableString *log)
{
    auto addDylib = ^(NSString *path) {
        if(path.length == 0) { return; }
        if(![NSFileManager.defaultManager fileExistsAtPath:path])
        {
            [log appendFormat:@"Dylib input missing: %@\n", path];
            return;
        }
        dylibs.push_back(string(path.UTF8String));
        [log appendFormat:@"Queued dylib injection: %@\n", path.lastPathComponent];
    };
    for(NSString *path in LBIStringArray(plan, @"modify", @"existingDylibs"))
    {
        addDylib(path);
    }
    for(NSString *path in LBIStringArray(plan, @"modify", @"frameworksAndPlugins"))
    {
        NSString *ext = path.pathExtension.lowercaseString;
        if([ext isEqualToString:@"framework"] || [ext isEqualToString:@"dylib"])
        {
            if([ext isEqualToString:@"dylib"]) { addDylib(path); }
            else { LBICopyIntoAppSubdir(path, appDir, @"Frameworks", log); }
        }
        else if([ext isEqualToString:@"appex"] || [ext isEqualToString:@"plugin"])
        {
            LBICopyIntoAppSubdir(path, appDir, @"PlugIns", log);
        }
        else
        {
            [log appendFormat:@"Unsupported framework/plugin type for now: %@\n", path.lastPathComponent];
        }
    }
    for(NSString *path in LBIStringArray(plan, @"modify", @"tweaks"))
    {
        NSString *ext = path.pathExtension.lowercaseString;
        if([ext isEqualToString:@"dylib"]) { addDylib(path); }
        else if([ext isEqualToString:@"framework"]) { LBICopyIntoAppSubdir(path, appDir, @"Frameworks", log); }
        else if([ext isEqualToString:@"appex"] || [ext isEqualToString:@"plugin"]) { LBICopyIntoAppSubdir(path, appDir, @"PlugIns", log); }
        else { [log appendFormat:@"Unsupported tweak input type for now: %@\n", path.lastPathComponent]; }
    }
}

static char *LBIKittyStoreSign(NSDictionary *request, NSMutableString *log)
{
    NSString *planPath = LBIString(request, @"hostInputPath");
    NSString *hostWorkDir = LBIString(request, @"hostWorkDir");
    NSString *fakefsBuildDir = LBIString(request, @"fakefsBuildDir");
    if(hostWorkDir.length == 0) { hostWorkDir = LBIString(request, @"buildDir"); }
    if(fakefsBuildDir.length == 0) { fakefsBuildDir = @"/root/.litter/builds/kittystore"; }
    NSDictionary *plan = LBIJSONDictionaryFromFile(planPath, log);
    if(plan.count == 0) { return LBICopyResponse(65, @"kittystore-plan-invalid", log); }

    NSString *ipaPath = LBINestedString(plan, @"app", @"ipa");
    if(ipaPath.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:ipaPath])
    {
        [log appendFormat:@"IPA input is missing: %@\n", ipaPath ?: @""];
        return LBICopyResponse(66, @"kittystore-ipa-missing", log);
    }

    NSString *workRoot = [hostWorkDir stringByAppendingPathComponent:@"KittyStoreZsignWork"];
    NSString *extractRoot = [workRoot stringByAppendingPathComponent:@"Extracted"];
    NSString *artifactDir = [hostWorkDir stringByAppendingPathComponent:@"Artifacts"];
    [NSFileManager.defaultManager removeItemAtPath:workRoot error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:artifactDir withIntermediateDirectories:YES attributes:nil error:nil];

    [log appendFormat:@"Feather Zsign extract: %@ -> %@\n", ipaPath, extractRoot];
    if(!Zip::Extract(ipaPath.UTF8String, extractRoot.UTF8String))
    {
        return LBICopyResponse(74, @"kittystore-unzip-failed", log);
    }
    NSString *appDir = LBIKittyStoreFindApp(extractRoot);
    if(appDir.length == 0)
    {
        [log appendString:@"Could not find Payload/*.app after IPA extraction.\n"];
        return LBICopyResponse(65, @"kittystore-payload-missing", log);
    }

    LBIKittyStoreModifyInfoPlist(plan, appDir, log);
    vector<string> dylibs;
    LBIKittyStoreCollectInputs(plan, appDir, dylibs, log);

    NSString *signingType = LBINestedString(plan, @"signing", @"type").lowercaseString;
    if(signingType.length == 0 || [signingType isEqualToString:@"standard"]) { signingType = @"default"; }
    BOOL adhocSign = [signingType isEqualToString:@"adhoc"];
    NSString *certificatePath = @"";
    NSString *password = @"";
    NSString *provisionPath = @"";
    if(!adhocSign)
    {
        certificatePath = LBIKittyStoreCertificatePath(hostWorkDir, log);
        if(certificatePath.length == 0) { return LBICopyResponse(78, @"kittystore-certificate-missing", log); }
        password = [NSUserDefaults.standardUserDefaults stringForKey:@"LCCertificatePassword"] ?: @"";
        provisionPath = LBIKittyStoreProvisionPath(plan, appDir, log);
        if(provisionPath.length == 0) { return LBICopyResponse(78, @"kittystore-profile-missing", log); }
    }
    NSString *entitlementsPath = LBIKittyStoreWriteEntitlements(plan, hostWorkDir, log);

    ZSignAsset zsa;
    if(adhocSign)
    {
        [log appendString:@"Running Feather Zsign ad-hoc signing; certificate and provisioning profile are not required.\n"];
        if(!zsa.Init("", "", "", entitlementsPath.UTF8String, "", true, false, false))
        {
            [log appendString:@"Feather Zsign could not prepare ad-hoc signing assets. Check the custom entitlements plist.\n"];
            return LBICopyResponse(78, @"kittystore-adhoc-invalid", log);
        }
    }
    else if(!zsa.Init("", certificatePath.UTF8String, provisionPath.UTF8String, entitlementsPath.UTF8String, password.UTF8String, false, false, false))
    {
        [log appendString:@"Feather Zsign could not load the certificate/profile. The .p12 password may be wrong, the cert may lack a private key, or the profile may not match.\n"];
        return LBICopyResponse(78, @"kittystore-certificate-invalid", log);
    }

    NSString *bundleID = LBINestedString(plan, @"app", @"bundleIdentifier");
    NSString *version = LBINestedString(plan, @"app", @"version");
    NSString *displayName = LBINestedString(plan, @"app", @"name");
    vector<string> removeDylibs;
    ZBundle bundle;
    bundle.m_bEnableDocuments = LBINestedBool(plan, @"properties", @"fileSharing") || LBINestedBool(plan, @"properties", @"iTunesFileSharing");
    BOOL removeProvision = LBINestedBool(plan, @"properties", @"removeProvisioning");
    BOOL forceSign = [signingType isEqualToString:@"force"] || adhocSign;
    BOOL weakInject = NO;
    NSString *injectPath = LBINestedString(plan, @"properties", @"injectPath");
    if(injectPath.length > 0 && ![injectPath isEqualToString:@"@executable_path"])
    {
        [log appendFormat:@"Feather Zsign bundle injection uses @executable_path for dylib load commands; requested injectPath %@ is recorded but not applied by this backend.\n", injectPath];
    }
    [log appendFormat:@"Running Feather Zsign bundle signer. type=%@ force=%@ weakInject=%@\n", signingType, forceSign ? @"yes" : @"no", weakInject ? @"yes" : @"no"];
    bool signedOK = bundle.SignFolder(&zsa,
                                      string(extractRoot.UTF8String),
                                      string(bundleID.UTF8String),
                                      string(version.UTF8String),
                                      string(displayName.UTF8String),
                                      dylibs,
                                      removeDylibs,
                                      forceSign,
                                      weakInject,
                                      false,
                                      removeProvision);
    if(!signedOK)
    {
        [log appendString:@"Feather Zsign failed while signing the extracted app bundle.\n"];
        return LBICopyResponse(74, @"kittystore-sign-failed", log);
    }

    NSString *safeName = LBISafeFileComponent(displayName.length > 0 ? displayName : appDir.lastPathComponent.stringByDeletingPathExtension, @"Signed");
    NSString *outputHost = [artifactDir stringByAppendingPathComponent:[safeName stringByAppendingString:@"-signed.ipa"]];
    string archiveRoot = string(extractRoot.UTF8String);
    if(!bundle.m_strAppFolder.empty())
    {
        size_t pos = bundle.m_strAppFolder.rfind("Payload");
        if(pos != string::npos && pos > 0) { archiveRoot = bundle.m_strAppFolder.substr(0, pos - 1); }
    }
    [log appendFormat:@"Feather Zsign archive: %@\n", outputHost];
    if(!Zip::Archive(archiveRoot, string(outputHost.UTF8String), 6))
    {
        return LBICopyResponse(74, @"kittystore-archive-failed", log);
    }

    NSString *fakefsPath = LBIString(plan, @"outputFakefsPath");
    if(fakefsPath.length == 0) { fakefsPath = [fakefsBuildDir stringByAppendingPathComponent:outputHost.lastPathComponent]; }
    [log appendFormat:@"Signed IPA artifact: %@ -> %@\n", outputHost, fakefsPath];
    NSArray *artifacts = @[@{@"hostPath": outputHost, @"fakefsPath": fakefsPath}];
    return LBICopyResponseWithArtifacts(0, @"kittystore-sign-ok", log, artifacts);
}
#endif

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
        NSString *buildKitRoot = LBIString(request, @"buildKitRoot");
        NSString *toolchainRoot = LBIString(request, @"toolchainRoot");
        NSString *sdkRoot = LBIString(request, @"sdkRoot");
        NSString *swiftResourceDir = LBIString(request, @"swiftResourceDir");
        NSString *clangResourceDir = LBIString(request, @"clangResourceDir");
        NSString *cxxStandardLibraryIncludeDir = LBIString(request, @"cxxStandardLibraryIncludeDir");
        NSString *hostInputPath = LBIString(request, @"hostInputPath");
        NSString *hostProjectPath = LBIString(request, @"hostProjectPath");
        NSString *hostWorkDir = LBIString(request, @"hostWorkDir");
        NSMutableString *log = [NSMutableString stringWithFormat:@"Litter in-process Nyxian BuildKit\nrequest=%@\ncommand=%@\n", requestPath, command];

        if([command isEqualToString:@"litter-kittystore-sign"])
        {
#ifdef LBN_ENABLE_KITTYSTORE_SIGNER
            return LBIKittyStoreSign(request, log);
#else
            [log appendString:@"This native BuildKit framework was built without LBN_ENABLE_KITTYSTORE_SIGNER. Rebuild private BuildKit assets with the vendored Feather/Zsign source enabled.\n"];
            return LBICopyResponse(78, @"kittystore-signer-not-built", log);
#endif
        }

        if([command isEqualToString:@"litter-kittystore-install"] || [command isEqualToString:@"litter-kittystore-refresh"])
        {
            [log appendString:@"SideStore minimuxer source is vendored, but this native BuildKit framework was not linked with the minimuxer static library. Rebuild the private app with a Minimuxer xcframework/staticlib bridge before install/refresh can run on device.\n"];
            return LBICopyResponse(78, @"sidestore-minimuxer-not-linked", log);
        }

        if([command isEqualToString:@"litter-swift-check"])
        {
            NSString *source = hostInputPath.length > 0 ? hostInputPath : LBIWords(args).firstObject;
            if(source.length == 0) { return LBICopyResponse(64, @"missing-input", @"No Swift input was supplied.\n"); }
            NSMutableArray<NSString *> *driverArgs = [NSMutableArray arrayWithArray:@[@"-typecheck", @"-sdk", sdkRoot, @"-target", @"arm64-apple-ios18.0"]];
            LBIAppendSwiftSDKCompatibilityFlags(driverArgs);
            LBIAppendSwiftClangResourceDir(driverArgs, clangResourceDir, log);
            if(!LBIAppendSwiftResourceDir(driverArgs, swiftResourceDir, toolchainRoot, buildKitRoot, sdkRoot, log)) { return LBICopyResponse(78, @"swift-resource-dir-missing", log); }
            [driverArgs addObject:source];
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
                NSMutableArray<NSString *> *driverArgs = [NSMutableArray arrayWithArray:@[@"-typecheck", @"-sdk", sdkRoot, @"-target", @"arm64-apple-ios18.0"]];
                LBIAppendSwiftSDKCompatibilityFlags(driverArgs);
                LBIAppendSwiftClangResourceDir(driverArgs, clangResourceDir, log);
                if(!LBIAppendSwiftResourceDir(driverArgs, swiftResourceDir, toolchainRoot, buildKitRoot, sdkRoot, log)) { return LBICopyResponse(78, @"swift-resource-dir-missing", log); }
                [driverArgs addObject:source];
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
            [driverArgs addObjectsFromArray:@[@"-sdk", sdkRoot, @"-target", @"arm64-apple-ios18.0", @"-o", hostOutput]];
            LBIAppendSwiftSDKCompatibilityFlags(driverArgs);
            LBIAppendSwiftClangResourceDir(driverArgs, clangResourceDir, log);
            if(!LBIAppendSwiftResourceDir(driverArgs, swiftResourceDir, toolchainRoot, buildKitRoot, sdkRoot, log)) { return LBICopyResponse(78, @"swift-resource-dir-missing", log); }
            [driverArgs addObject:source];
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
            LBIAppendClangResourceDir(driverArgs, clangResourceDir, log);
            LBIAppendCXXStandardLibraryHeaders(driverArgs, cxxStandardLibraryIncludeDir, source, log);
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
            LBIAppendClangResourceDir(driverArgs, clangResourceDir, log);
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
            LBIAppendSwiftSDKCompatibilityFlags(driverArgs);
            LBIAppendSwiftClangResourceDir(driverArgs, clangResourceDir, log);
            if(!LBIAppendSwiftResourceDir(driverArgs, swiftResourceDir, toolchainRoot, buildKitRoot, sdkRoot, log)) { return LBICopyResponse(78, @"swift-resource-dir-missing", log); }
            [driverArgs addObjectsFromArray:@[@"-framework", @"UIKit", @"-framework", @"Foundation"]];
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
