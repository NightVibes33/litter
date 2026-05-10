#import <Foundation/Foundation.h>
#import <MobileDevelopmentKit/MDKDriver.h>
#import <MobileDevelopmentKit/MDKJob.h>
#import <MobileDevelopmentKit/MDKDiagnostic.h>

#include <zlib.h>
#include <stdlib.h>
#include <string.h>

static NSString *LBIString(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static char *LBICopyResponse(int exitCode, NSString *status, NSString *log)
{
    NSDictionary *response = @{@"exitCode": @(exitCode), @"status": status ?: @"unknown", @"log": log ?: @""};
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"exitCode\":70,\"status\":\"response-encode-failed\",\"log\":\"could not encode response\"}";
    return strdup(json.UTF8String);
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
            NSString *deployment = [manifest[@"deploymentTarget"] isKindOfClass:NSString.class] ? manifest[@"deploymentTarget"] : @"18.0";
            NSString *productName = [manifest[@"name"] isKindOfClass:NSString.class] ? manifest[@"name"] : @"LitterApp";
            NSString *outDir = [hostWorkDir stringByAppendingPathComponent:@"BuildProducts"];
            NSString *appDir = [outDir stringByAppendingPathComponent:[productName stringByAppendingPathExtension:@"app"]];
            NSString *executable = [appDir stringByAppendingPathComponent:productName];
            [NSFileManager.defaultManager createDirectoryAtPath:appDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSMutableArray<NSString *> *driverArgs = [NSMutableArray arrayWithArray:@[@"-sdk", sdkRoot, @"-target", [@"arm64-apple-ios" stringByAppendingString:deployment], @"-o", executable]];
            [driverArgs addObjectsFromArray:sources];
            int code = LBIRunSwiftDriver(driverArgs, log);
            if(code != 0) { return LBICopyResponse(code, @"swift-build-failed", log); }
            [log appendFormat:@"Built app executable: %@\n", executable];
            [log appendString:@"IPA zip packaging is delegated to the BuildKit runner/packager layer when present; in-process compiler output is staged under BuildProducts.\n"];
            return LBICopyResponse(0, @"swift-build-ok", log);
        }

        return NULL;
    }
}
