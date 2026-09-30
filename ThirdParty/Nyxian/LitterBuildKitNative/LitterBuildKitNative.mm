#import <Foundation/Foundation.h>
#ifdef LBN_ENABLE_BAD_QUERY
#import <UIKit/UIKit.h>
#endif

#include "LitterBuildKitNative.h"

#ifdef LBN_ENABLE_BAD_QUERY
extern "C" {
#include "bad_query.h"
}
#endif

#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <string>
#include <vector>

extern char **environ;

#ifdef LBN_ENABLE_INPROCESS
extern "C" char *LBNRunInProcessBuildKit(NSDictionary *request, NSString *requestPath);
#endif

static NSString *LBNString(NSDictionary *dictionary, NSString *key)
{
    id value = dictionary[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static char *LBNCopyCString(NSDictionary *response)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:&error];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if(json.length == 0)
    {
        json = [NSString stringWithFormat:@"{\"exitCode\":70,\"status\":\"response-encode-failed\",\"log\":\"%@\"}", error.localizedDescription ?: @"unknown error"];
    }
    return strdup(json.UTF8String);
}

static char *LBNResponse(int exitCode, NSString *status, NSString *log)
{
    return LBNCopyCString(@{
        @"exitCode": @(exitCode),
        @"status": status ?: @"unknown",
        @"log": log ?: @""
    });
}

#ifdef LBN_ENABLE_BAD_QUERY
#ifndef BAD_QUERY_UPSTREAM_COMMIT
#define BAD_QUERY_UPSTREAM_COMMIT "unknown"
#endif

static NSMutableSet<NSNumber *> *LBNBadQueryHandles(void)
{
    static NSMutableSet<NSNumber *> *handles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handles = [NSMutableSet set];
    });
    return handles;
}

static NSArray<NSString *> *LBNBadQueryTokens(NSString *args)
{
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    unichar quote = 0;
    BOOL escaping = NO;

    for(NSUInteger index = 0; index < args.length; index++)
    {
        unichar character = [args characterAtIndex:index];

        if(escaping)
        {
            [current appendFormat:@"%C", character];
            escaping = NO;
            continue;
        }

        if(character == '\\' && quote != '\'')
        {
            escaping = YES;
            continue;
        }

        if(quote != 0)
        {
            if(character == quote)
            {
                quote = 0;
            }
            else
            {
                [current appendFormat:@"%C", character];
            }
            continue;
        }

        if(character == '\'' || character == '"')
        {
            quote = character;
            continue;
        }

        if([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:character])
        {
            if(current.length > 0)
            {
                [tokens addObject:[current copy]];
                [current setString:@""];
            }
            continue;
        }

        [current appendFormat:@"%C", character];
    }

    if(escaping) { [current appendString:@"\\"]; }
    if(current.length > 0) { [tokens addObject:[current copy]]; }
    return tokens;
}

static NSString *LBNBadQueryOption(NSArray<NSString *> *tokens, NSString *name)
{
    NSUInteger index = [tokens indexOfObject:name];
    if(index == NSNotFound || index + 1 >= tokens.count) { return nil; }
    return tokens[index + 1];
}

static NSString *LBNBadQueryFailure(int64_t code)
{
    switch(code)
    {
        case -255: return @"path must be absolute";
        case -254: return @"target path does not exist";
        case -1: return @"private container/sandbox symbols could not be loaded";
        case -2: return @"container query could not be created";
        case -3: return @"container query returned no result";
        case -4: return @"kernel refused to issue a sandbox extension";
        case -5: return @"path traversal string allocation failed";
        default: return [NSString stringWithFormat:@"BadQuery returned %lld", code];
    }
}

static UIViewController *LBNBadQueryTopViewController(void)
{
    UIWindow *window = nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
    {
        if(scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) { continue; }
        for(UIWindow *candidate in ((UIWindowScene *)scene).windows)
        {
            if(candidate.isKeyWindow) { window = candidate; break; }
            if(window == nil && !candidate.hidden) { window = candidate; }
        }
        if(window != nil) { break; }
    }
    UIViewController *controller = window.rootViewController;
    while(controller.presentedViewController != nil) { controller = controller.presentedViewController; }
    if([controller isKindOfClass:UINavigationController.class]) { controller = ((UINavigationController *)controller).visibleViewController; }
    if([controller isKindOfClass:UITabBarController.class]) { controller = ((UITabBarController *)controller).selectedViewController; }
    return controller;
}

static BOOL LBNBadQueryRequireApproval(NSString *args)
{
    // Fail closed if the bridge is invoked on the UI thread: blocking it while
    // waiting for an alert response would deadlock. Normal BuildKit requests
    // execute off-main.
    if(NSThread.isMainThread) { return NO; }

    __block BOOL approved = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSString *exactCommand = [NSString stringWithFormat:@"bad-query %@", args ?: @""];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = LBNBadQueryTopViewController();
        if(presenter == nil)
        {
            dispatch_semaphore_signal(semaphore);
            return;
        }
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Allow BadQuery access?"
            message:[NSString stringWithFormat:@"Alley Cãt is requesting this exact native operation:\n\n%@\n\nApproval applies once to this command only.", exactCommand]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Deny" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
            dispatch_semaphore_signal(semaphore);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Allow Once" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            approved = YES;
            dispatch_semaphore_signal(semaphore);
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
    // Never leave an agent/tool call blocked forever if presentation fails.
    long result = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 60LL * NSEC_PER_SEC));
    return result == 0 && approved;
}

static char *LBNRunBadQuery(NSString *args)
{
    NSArray<NSString *> *tokens = LBNBadQueryTokens(args ?: @"");
    NSString *operation = tokens.firstObject ?: @"help";
    if([operation isEqualToString:@"help"] || [operation isEqualToString:@"--help"] || [operation isEqualToString:@"-h"])
    {
        NSString *usage =
            @"Real forcequitOS/bad_query runtime\n"
             "  bad-query status\n"
             "  bad-query acquire --path /absolute/path [--create] [--group-id group.id] [--is-group]\n"
             "  bad-query list --path /absolute/path --max-inode N\n"
             "  bad-query release --handle N\n"
             "  bad-query release-all\n"
             "Sandbox-extension handles remain active in the Alley Cat process until released or the process exits.\n";
        return LBNResponse(0, @"bad-query-help", usage);
    }

    if([operation isEqualToString:@"status"])
    {
        NSUInteger count = 0;
        @synchronized(LBNBadQueryHandles()) { count = LBNBadQueryHandles().count; }
        NSString *log = [NSString stringWithFormat:
            @"BadQuery native runtime\nupstream=forcequitOS/bad_query\ncommit=%s\nactiveHandles=%lu\n",
            BAD_QUERY_UPSTREAM_COMMIT, (unsigned long)count];
        return LBNResponse(0, @"bad-query-ready", log);
    }

    NSSet<NSString *> *approvalOperations = [NSSet setWithArray:@[@"acquire", @"list", @"release", @"release-all"]];
    if([approvalOperations containsObject:operation] && !LBNBadQueryRequireApproval(args))
    {
        return LBNResponse(77, @"bad-query-user-denied", @"BadQuery operation was not approved by the user at the native runtime boundary.\n");
    }

    if([operation isEqualToString:@"acquire"])
    {
        NSString *path = LBNBadQueryOption(tokens, @"--path");
        if(path.length == 0 && tokens.count > 1 && ![tokens[1] hasPrefix:@"-"]) { path = tokens[1]; }
        if(path.length == 0 || ![path hasPrefix:@"/"])
        {
            return LBNResponse(64, @"bad-query-usage", @"acquire requires --path /absolute/path\n");
        }
        BOOL create = [tokens containsObject:@"--create"];
        BOOL isGroup = [tokens containsObject:@"--is-group"];
        NSString *groupID = LBNBadQueryOption(tokens, @"--group-id");
        int64_t handle = bad_query(
            (char *)path.fileSystemRepresentation,
            create,
            groupID.length > 0 ? (char *)groupID.UTF8String : NULL,
            isGroup
        );
        if(handle < 0)
        {
            NSString *log = [NSString stringWithFormat:
                @"BadQuery acquire failed\npath=%@\ncreate=%d\ngroupIdentifier=%@\nisGroup=%d\nresult=%lld\nreason=%@\n",
                path, create, groupID ?: @"(systemgroup default)", isGroup, handle, LBNBadQueryFailure(handle)];
            return LBNResponse(77, @"bad-query-denied", log);
        }
        @synchronized(LBNBadQueryHandles()) { [LBNBadQueryHandles() addObject:@(handle)]; }
        NSString *log = [NSString stringWithFormat:
            @"BadQuery acquire succeeded\npath=%@\ncreate=%d\ngroupIdentifier=%@\nisGroup=%d\nhandle=%lld\n",
            path, create, groupID ?: @"(systemgroup default)", isGroup, handle];
        return LBNResponse(0, @"bad-query-acquired", log);
    }

    if([operation isEqualToString:@"list"])
    {
        NSString *path = LBNBadQueryOption(tokens, @"--path");
        if(path.length == 0 && tokens.count > 1 && ![tokens[1] hasPrefix:@"-"]) { path = tokens[1]; }
        NSString *maxText = LBNBadQueryOption(tokens, @"--max-inode");
        long long maxInode = maxText.length > 0 ? maxText.longLongValue : 1000000LL;
        if(path.length == 0 || ![path hasPrefix:@"/"] || maxInode <= 0)
        {
            return LBNResponse(64, @"bad-query-usage", @"list requires --path /absolute/path [--max-inode N]\n");
        }
        char *listing = bad_query_list((char *)path.fileSystemRepresentation, (int64_t)maxInode);
        if(listing == NULL)
        {
            return LBNResponse(74, @"bad-query-list-failed",
                [NSString stringWithFormat:@"bad_query_list returned NULL\npath=%@\nmaxInode=%lld\n", path, maxInode]);
        }
        NSString *entries = [NSString stringWithUTF8String:listing] ?: @"";
        free(listing);
        NSString *log = [NSString stringWithFormat:
            @"BadQuery inode enumeration\npath=%@\nmaxInode=%lld\n\n%@",
            path, maxInode, entries];
        return LBNResponse(0, @"bad-query-list", log);
    }

    if([operation isEqualToString:@"release"])
    {
        NSString *handleText = LBNBadQueryOption(tokens, @"--handle");
        if(handleText.length == 0 && tokens.count > 1 && ![tokens[1] hasPrefix:@"-"]) { handleText = tokens[1]; }
        long long parsed = handleText.longLongValue;
        NSNumber *handleNumber = @(parsed);
        BOOL tracked = NO;
        @synchronized(LBNBadQueryHandles()) { tracked = [LBNBadQueryHandles() containsObject:handleNumber]; }
        if(handleText.length == 0 || parsed < 0 || !tracked)
        {
            return LBNResponse(66, @"bad-query-handle-not-found", @"release requires a live handle returned by this BadQuery runtime\n");
        }
        bad_query_release((int64_t)parsed);
        @synchronized(LBNBadQueryHandles()) { [LBNBadQueryHandles() removeObject:handleNumber]; }
        return LBNResponse(0, @"bad-query-released",
            [NSString stringWithFormat:@"Released BadQuery handle %lld\n", parsed]);
    }

    if([operation isEqualToString:@"release-all"])
    {
        NSArray<NSNumber *> *handles = nil;
        @synchronized(LBNBadQueryHandles())
        {
            handles = LBNBadQueryHandles().allObjects;
            [LBNBadQueryHandles() removeAllObjects];
        }
        for(NSNumber *number in handles) { bad_query_release(number.longLongValue); }
        return LBNResponse(0, @"bad-query-released-all",
            [NSString stringWithFormat:@"Released %lu BadQuery handles\n", (unsigned long)handles.count]);
    }

    return LBNResponse(64, @"bad-query-usage", @"Unknown BadQuery operation. Run: bad-query help\n");
}
#endif

static NSDictionary *LBNParseRequest(const char *requestJSON, NSString **error)
{
    if(requestJSON == NULL)
    {
        if(error) { *error = @"request_json was null"; }
        return nil;
    }

    NSData *data = [[NSString stringWithUTF8String:requestJSON] dataUsingEncoding:NSUTF8StringEncoding];
    if(data.length == 0)
    {
        if(error) { *error = @"request_json was empty or not valid UTF-8"; }
        return nil;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if(![object isKindOfClass:NSDictionary.class])
    {
        if(error) { *error = jsonError.localizedDescription ?: @"request_json must be a JSON object"; }
        return nil;
    }
    return object;
}

static NSString *LBNFindRunner(NSString *buildKitRoot, NSString *toolchainRoot)
{
    NSString *bundleToolchainRoot = [[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"BuildKitAssets"] stringByAppendingPathComponent:@"Toolchains/Nyxian"];
    NSArray<NSString *> *candidates = @[
        [bundleToolchainRoot stringByAppendingPathComponent:@"bin/litter-buildkit-runner"],
        [bundleToolchainRoot stringByAppendingPathComponent:@"bin/nyxian-buildkit"],
        [toolchainRoot stringByAppendingPathComponent:@"bin/litter-buildkit-runner"],
        [toolchainRoot stringByAppendingPathComponent:@"bin/nyxian-buildkit"],
        [buildKitRoot stringByAppendingPathComponent:@"bin/litter-buildkit-runner"],
        [buildKitRoot stringByAppendingPathComponent:@"bin/nyxian-buildkit"]
    ];

    NSFileManager *fm = NSFileManager.defaultManager;
    for(NSString *candidate in candidates)
    {
        if([fm isExecutableFileAtPath:candidate])
        {
            return candidate;
        }
    }
    return nil;
}

static NSString *LBNWriteRequestFile(NSDictionary *request, NSString *requestDir, NSString **error)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if(requestDir.length == 0)
    {
        if(error) { *error = @"native request directory was empty"; }
        return nil;
    }

    NSError *dirError = nil;
    if(![fm createDirectoryAtPath:requestDir withIntermediateDirectories:YES attributes:nil error:&dirError])
    {
        if(error) { *error = dirError.localizedDescription ?: @"could not create native request directory"; }
        return nil;
    }

    NSString *path = [requestDir stringByAppendingPathComponent:@"request.json"];
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:NSJSONWritingPrettyPrinted error:&jsonError];
    if(data == nil)
    {
        if(error) { *error = jsonError.localizedDescription ?: @"could not encode request JSON"; }
        return nil;
    }

    NSError *writeError = nil;
    if(![data writeToFile:path options:NSDataWritingAtomic error:&writeError])
    {
        if(error) { *error = writeError.localizedDescription ?: @"could not write request file"; }
        return nil;
    }
    return path;
}

static int LBNRunRunner(NSString *runner, NSArray<NSString *> *arguments, NSString **capturedOutput)
{
    int pipeFD[2];
    if(pipe(pipeFD) != 0)
    {
        if(capturedOutput) { *capturedOutput = @"pipe() failed before launching Nyxian runner\n"; }
        return 70;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipeFD[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipeFD[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipeFD[0]);

    std::vector<std::string> storage;
    storage.reserve(arguments.count + 1);
    storage.emplace_back(runner.UTF8String ?: "");
    for(NSString *argument in arguments)
    {
        storage.emplace_back(argument.UTF8String ?: "");
    }

    std::vector<char *> argv;
    argv.reserve(storage.size() + 1);
    for(std::string &item : storage)
    {
        argv.push_back(const_cast<char *>(item.c_str()));
    }
    argv.push_back(nullptr);

    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, runner.fileSystemRepresentation, &actions, NULL, argv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipeFD[1]);

    NSMutableData *output = [NSMutableData data];
    char buffer[4096];
    ssize_t count = 0;
    while((count = read(pipeFD[0], buffer, sizeof(buffer))) > 0)
    {
        [output appendBytes:buffer length:(NSUInteger)count];
    }
    close(pipeFD[0]);

    NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] ?: @"";
    if(spawnResult != 0)
    {
        if(capturedOutput)
        {
            *capturedOutput = [NSString stringWithFormat:@"posix_spawn failed for %@: %s\n%@", runner, strerror(spawnResult), text];
        }
        return 70;
    }

    int status = 0;
    waitpid(pid, &status, 0);
    if(capturedOutput) { *capturedOutput = text; }
    if(WIFEXITED(status)) { return WEXITSTATUS(status); }
    if(WIFSIGNALED(status)) { return 128 + WTERMSIG(status); }
    return 70;
}

const char *litter_buildkit_run_json(const char *request_json)
{
    @autoreleasepool
    {
        NSString *parseError = nil;
        NSDictionary *request = LBNParseRequest(request_json, &parseError);
        if(request == nil)
        {
            return LBNResponse(64, @"request-invalid", parseError ?: @"Invalid BuildKit request JSON");
        }

        NSString *command = LBNString(request, @"command");
        NSString *args = LBNString(request, @"args");
        NSString *cwd = LBNString(request, @"cwd");
        NSString *buildDir = LBNString(request, @"buildDir");
        NSString *buildKitRoot = LBNString(request, @"buildKitRoot");
        NSString *toolchainRoot = LBNString(request, @"toolchainRoot");
        NSString *sdkRoot = LBNString(request, @"sdkRoot");
        NSString *hostWorkDir = LBNString(request, @"hostWorkDir");

        if(command.length == 0 || buildDir.length == 0 || buildKitRoot.length == 0 || toolchainRoot.length == 0 || sdkRoot.length == 0)
        {
            return LBNResponse(64, @"request-missing-fields", @"BuildKit native request requires command, buildDir, buildKitRoot, toolchainRoot, and sdkRoot.\n");
        }

#ifdef LBN_ENABLE_BAD_QUERY
        if([command isEqualToString:@"bad-query"])
        {
            return LBNRunBadQuery(args);
        }
#endif

        NSString *writeError = nil;
        NSString *requestDirectory = hostWorkDir.length > 0 ? hostWorkDir : buildDir;
        NSString *requestPath = LBNWriteRequestFile(request, requestDirectory, &writeError);
        if(requestPath == nil)
        {
            return LBNResponse(73, @"request-write-failed", writeError ?: @"Could not write native BuildKit request file.\n");
        }

#ifdef LBN_ENABLE_INPROCESS
        char *inProcessResponse = LBNRunInProcessBuildKit(request, requestPath);
        if(inProcessResponse != NULL)
        {
            return inProcessResponse;
        }
#endif

        NSString *runner = LBNFindRunner(buildKitRoot, toolchainRoot);
        if(runner.length == 0)
        {
            NSString *log = [NSString stringWithFormat:@"Native BuildKit framework loaded, but no Nyxian runner was found.\nExpected one of the bundled or installed runner paths under BuildKitAssets/Toolchains/Nyxian/bin or Documents/BuildKit.\n\nPackage a runner that links CoreCompiler.framework and consumes %@.\n",
                             requestPath];
            return LBNResponse(78, @"native-runner-missing", log);
        }

        NSArray<NSString *> *runnerArgs = @[
            command,
            @"--request", requestPath,
            @"--cwd", cwd.length > 0 ? cwd : @"/root",
            @"--args", args,
            @"--build-dir", buildDir,
            @"--buildkit-root", buildKitRoot,
            @"--toolchain-root", toolchainRoot,
            @"--sdk-root", sdkRoot
        ];
        NSString *hostProjectPath = LBNString(request, @"hostProjectPath");
        NSString *hostInputPath = LBNString(request, @"hostInputPath");
        if(hostWorkDir.length > 0) { runnerArgs = [runnerArgs arrayByAddingObjectsFromArray:@[@"--host-work-dir", hostWorkDir]]; }
        if(hostProjectPath.length > 0) { runnerArgs = [runnerArgs arrayByAddingObjectsFromArray:@[@"--host-project", hostProjectPath]]; }
        if(hostInputPath.length > 0) { runnerArgs = [runnerArgs arrayByAddingObjectsFromArray:@[@"--host-input", hostInputPath]]; }

        NSString *output = nil;
        int exitCode = LBNRunRunner(runner, runnerArgs, &output);
        NSString *status = exitCode == 0 ? @"native-ok" : @"native-failed";
        NSString *log = [NSString stringWithFormat:@"Runner: %@\nCommand: %@\nRequest: %@\n\n%@", runner, command, requestPath, output ?: @""];
        return LBNResponse(exitCode, status, log);
    }
}

const char *litter_bad_query_upstream_commit(void)
{
#ifdef LBN_ENABLE_BAD_QUERY
    return BAD_QUERY_UPSTREAM_COMMIT;
#else
    return NULL;
#endif
}

void litter_buildkit_free_string(const char *response_json)
{
    free((void *)response_json);
}
