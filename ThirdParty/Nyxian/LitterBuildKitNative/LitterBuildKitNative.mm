#import <Foundation/Foundation.h>

#include "LitterBuildKitNative.h"

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

static NSString *LBNWriteRequestFile(NSDictionary *request, NSString *buildDir, NSString **error)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *dirError = nil;
    if(![fm createDirectoryAtPath:buildDir withIntermediateDirectories:YES attributes:nil error:&dirError])
    {
        if(error) { *error = dirError.localizedDescription ?: @"could not create build directory"; }
        return nil;
    }

    NSString *path = [buildDir stringByAppendingPathComponent:@"request.json"];
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

        if(command.length == 0 || buildDir.length == 0 || buildKitRoot.length == 0 || toolchainRoot.length == 0 || sdkRoot.length == 0)
        {
            return LBNResponse(64, @"request-missing-fields", @"BuildKit native request requires command, buildDir, buildKitRoot, toolchainRoot, and sdkRoot.\n");
        }

        NSString *writeError = nil;
        NSString *requestPath = LBNWriteRequestFile(request, buildDir, &writeError);
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
        NSString *hostWorkDir = LBNString(request, @"hostWorkDir");
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

void litter_buildkit_free_string(const char *response_json)
{
    free((void *)response_json);
}
