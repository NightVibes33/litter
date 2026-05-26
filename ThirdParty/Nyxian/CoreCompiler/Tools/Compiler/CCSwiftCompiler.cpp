/*
 * MIT License
 *
 * Copyright (c) 2026 Kyle-Ye
 * Copyright (c) 2026 mach-port-t
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <CoreCompiler/CCSwiftCompiler.h>
#include <CoreCompiler/CCDiagnostic.h>
#include <CoreCompiler/CCFile.h>
#include <CoreCompiler/CCUtils.h>
#include <CoreCompiler/CCUtilsPrivate.h>
#include <swift/FrontendTool/FrontendTool.h>
#include <swift/Frontend/Frontend.h>
#include <swift/Frontend/PrintingDiagnosticConsumer.h>
#include <swift/Basic/InitializeSwiftModules.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/ErrorHandling.h>
#include <fcntl.h>
#include <mutex>
#include <stdio.h>
#include <unistd.h>

struct CapturedDiag {
    swift::DiagID id;
    swift::DiagnosticKind kind;
    std::string message;
    std::string file;
    unsigned line = 0, column = 0;
    /* add ranges / fixits / category / educationalNotes if you need them */
};

class CapturingConsumer : public swift::DiagnosticConsumer {
public:
    std::vector<CapturedDiag> diags;

    void handleDiagnostic(swift::SourceManager &SM,
                          const swift::DiagnosticInfo &Info) override
    {
        CapturedDiag d;
        d.id = Info.ID;
        d.kind = Info.Kind;

        /* render FormatString + FormatArgs into a real string. */
        llvm::SmallString<256> buf;
        {
            llvm::raw_svector_ostream os(buf);
            swift::DiagnosticEngine::formatDiagnosticText(os, Info.FormatString, Info.FormatArgs);
        }
        d.message = std::string(buf);

        if(Info.Loc.isValid())
        {
            auto lc = SM.getPresumedLineAndColumnForLoc(Info.Loc);
            d.line = lc.first;
            d.column = lc.second;
            d.file = SM.getDisplayNameForLoc(Info.Loc).str();
        }
        diags.push_back(std::move(d));
    }
};

class MyObserver : public swift::FrontendObserver {
public:
    std::string primaryFile;
    CapturingConsumer consumer;
    
    void parsedArgs(swift::CompilerInvocation &invocation) override
    {
        auto &io = invocation.getFrontendOptions().InputsAndOutputs;
        if(io.hasPrimaryInputs())
        {
            io.forEachPrimaryInput([&](const swift::InputFile &f) -> bool
            {
                primaryFile = f.getFileName();
                return true;
            });
        }
        else
        {
            /* TODO: implement wmo support */
            primaryFile = "wmo";
        }
    }
    
    void configuredCompiler(swift::CompilerInstance &CI) override
    {
        CI.addDiagnosticConsumer(&consumer);
    }
};

static std::once_flag SwiftModulesInitOnce;
static std::mutex SwiftFrontendExecutionMutex;

static CFStringRef CCStringCreateWithFileDescriptor(CFAllocatorRef allocator, int fd)
{
    if(fd < 0)
    {
        return CFStringCreateWithCString(allocator, "", kCFStringEncodingUTF8);
    }

    lseek(fd, 0, SEEK_SET);

    CFMutableDataRef data = CFDataCreateMutable(allocator, 0);
    if(data == nullptr)
    {
        return CFStringCreateWithCString(allocator, "", kCFStringEncodingUTF8);
    }

    char buffer[4096];
    ssize_t count = 0;
    while((count = read(fd, buffer, sizeof(buffer))) > 0)
    {
        CFDataAppendBytes(data, reinterpret_cast<const UInt8 *>(buffer), count);
    }

    CFStringRef string = CFStringCreateFromExternalRepresentation(allocator, data, kCFStringEncodingUTF8);
    CFRelease(data);

    if(string == nullptr)
    {
        return CFStringCreateWithCString(allocator, "", kCFStringEncodingUTF8);
    }

    return string;
}

static int CCOpenUnlinkedTempFile(void)
{
    char path[] = "/tmp/litter-swift-frontend.XXXXXX";
    int fd = mkstemp(path);
    if(fd >= 0)
    {
        unlink(path);
    }
    return fd;
}

static CFStringRef CCCreateSwiftFrontendOutput(CFAllocatorRef allocator, CFStringRef stdoutText, CFStringRef stderrText)
{
    CFMutableStringRef output = CFStringCreateMutable(allocator, 0);
    if(output == nullptr)
    {
        return CFStringCreateWithCString(allocator, "", kCFStringEncodingUTF8);
    }

    if(stderrText != nullptr && CFStringGetLength(stderrText) > 0)
    {
        CFStringAppend(output, CFSTR("Swift frontend stderr:\n"));
        CFStringAppend(output, stderrText);
        if(!CFStringHasSuffix(output, CFSTR("\n")))
        {
            CFStringAppend(output, CFSTR("\n"));
        }
    }

    if(stdoutText != nullptr && CFStringGetLength(stdoutText) > 0)
    {
        CFStringAppend(output, CFSTR("Swift frontend stdout:\n"));
        CFStringAppend(output, stdoutText);
        if(!CFStringHasSuffix(output, CFSTR("\n")))
        {
            CFStringAppend(output, CFSTR("\n"));
        }
    }

    return output;
}

static void CCAppendInternalDiagnostic(CFMutableArrayRef diagnostics, CFStringRef mainSource, CCDiagnosticLevel level, CFStringRef message)
{
    if(diagnostics == nullptr || message == nullptr || CFStringGetLength(message) == 0)
    {
        return;
    }

    CCDiagnosticRef diagnostic = CCDiagnosticCreate(kCFAllocatorSystemDefault, CCDiagnosticTypeInternal, level, mainSource, nullptr, message);
    if(diagnostic == nullptr)
    {
        return;
    }

    CFArrayAppendValue(diagnostics, diagnostic);
    CFRelease(diagnostic);
}

CC_EXPORT Boolean CCSwiftCompilerJobExecute(CCJobRef job,
                                            CFArrayRef *outDiagnostics,
                                            CFStringRef *outMainSource)
{
    assert(job != nullptr);
    assert(CCJobGetType(job) == CCJobTypeSwiftCompiler);
    
    CFArrayRef argsArray = CCJobGetArguments(job);
    
    llvm::SmallVector<std::string, 64> argStorage = CCArrayToStringVector(argsArray);
    llvm::SmallVector<const char *, 64> args = StringVectorToCStrings(argStorage);
    
    /* get_-frontend_out_of_my_way type shii */
    if(!args.empty() && std::strcmp(args.front(), "-frontend") == 0)
    {
        args.erase(args.begin());
    }
    
    std::call_once(SwiftModulesInitOnce, [] {
        initializeSwiftModules();
    });
    
    MyObserver obs;
    int status = 1;
    CFStringRef capturedStdout = nullptr;
    CFStringRef capturedStderr = nullptr;

    {
        std::lock_guard<std::mutex> lock(SwiftFrontendExecutionMutex);
        int stdoutFD = CCOpenUnlinkedTempFile();
        int stderrFD = CCOpenUnlinkedTempFile();
        int savedStdout = stdoutFD >= 0 ? dup(STDOUT_FILENO) : -1;
        int savedStderr = stderrFD >= 0 ? dup(STDERR_FILENO) : -1;

        if(stdoutFD >= 0 && savedStdout >= 0)
        {
            dup2(stdoutFD, STDOUT_FILENO);
        }
        if(stderrFD >= 0 && savedStderr >= 0)
        {
            dup2(stderrFD, STDERR_FILENO);
        }

        llvm::remove_fatal_error_handler();
        status = swift::performFrontend(args, "swift-frontend", reinterpret_cast<void *>(CCSwiftCompilerJobExecute), &obs);
        CCInstallLLVMFatalErrorHandler();

        fflush(stdout);
        fflush(stderr);

        if(stdoutFD >= 0)
        {
            capturedStdout = CCStringCreateWithFileDescriptor(kCFAllocatorSystemDefault, stdoutFD);
        }
        if(stderrFD >= 0)
        {
            capturedStderr = CCStringCreateWithFileDescriptor(kCFAllocatorSystemDefault, stderrFD);
        }

        if(savedStdout >= 0)
        {
            dup2(savedStdout, STDOUT_FILENO);
            close(savedStdout);
        }
        if(savedStderr >= 0)
        {
            dup2(savedStderr, STDERR_FILENO);
            close(savedStderr);
        }
        if(stdoutFD >= 0)
        {
            close(stdoutFD);
        }
        if(stderrFD >= 0)
        {
            close(stderrFD);
        }
    }

    if(outDiagnostics == nullptr)
    {
        if(capturedStdout != nullptr) { CFRelease(capturedStdout); }
        if(capturedStderr != nullptr) { CFRelease(capturedStderr); }
        return status == 0;
    }

    *outDiagnostics = CFArrayCreateMutable(kCFAllocatorSystemDefault, obs.consumer.diags.size() + 1, &kCFTypeArrayCallBacks);
    if(*outDiagnostics == nullptr)
    {
        if(capturedStdout != nullptr) { CFRelease(capturedStdout); }
        if(capturedStderr != nullptr) { CFRelease(capturedStderr); }
        return status == 0;
    }

    const char *mainSourceCString = obs.primaryFile.empty() ? "swift-frontend" : obs.primaryFile.c_str();
    CFStringRef mainSource = CFStringCreateWithCString(kCFAllocatorSystemDefault, mainSourceCString, kCFStringEncodingUTF8);
    if(mainSource == nullptr)
    {
        mainSource = CFRetain(CFSTR("swift-frontend"));
    }

    for(auto &d : obs.consumer.diags)
    {
        CCDiagnosticLevel level = CCDiagnosticLevelUnknown;
        
        switch(d.kind)
        {
            case swift::DiagnosticKind::Error:
                level = CCDiagnosticLevelError;
                break;
            case swift::DiagnosticKind::Warning:
                level = CCDiagnosticLevelWarning;
                break;
            case swift::DiagnosticKind::Remark:
                level = CCDiagnosticLevelRemark;
                break;
            case swift::DiagnosticKind::Note:
                level = CCDiagnosticLevelNote;
                break;
            default:
                break;
        }
        
        if(level == CCDiagnosticLevelUnknown)
        {
            continue;
        }
        
        CFStringRef messageStr = CFStringCreateWithCString(kCFAllocatorSystemDefault, d.message.c_str(), kCFStringEncodingUTF8);
        if(messageStr == nullptr)
        {
            continue;
        }
        
        CCFileSourceLocationRef fileSourceLocation = nullptr;
        CCFileRef file = CCFileCreateWithCString(kCFAllocatorSystemDefault, d.file.c_str(), kCFStringEncodingUTF8);
        if(file != nullptr)
        {
            CFURLRef fileURL = CCFileGetFileURL(file);
            fileSourceLocation = CCFileSourceLocationCreate(kCFAllocatorSystemDefault, fileURL, CCSourceLocationMake(d.line, d.column));
            CFRelease(file);
        }
        
        CCDiagnosticRef diagnostic = CCDiagnosticCreate(kCFAllocatorSystemDefault, CCDiagnosticTypeFile, level, mainSource, fileSourceLocation, messageStr);
        CFRelease(messageStr);
        if(fileSourceLocation != nullptr) { CFRelease(fileSourceLocation); }
        if(diagnostic == nullptr)
        {
            continue;
        }
        
        CFArrayAppendValue((CFMutableArrayRef)*outDiagnostics, diagnostic);
        CFRelease(diagnostic);
    }
    
    if(status != 0)
    {
        CFStringRef frontendOutput = CCCreateSwiftFrontendOutput(kCFAllocatorSystemDefault, capturedStdout, capturedStderr);
        if(frontendOutput != nullptr && CFStringGetLength(frontendOutput) > 0)
        {
            CCAppendInternalDiagnostic((CFMutableArrayRef)*outDiagnostics, mainSource, CCDiagnosticLevelError, frontendOutput);
        }
        else if(CFArrayGetCount(*outDiagnostics) == 0)
        {
            CCAppendInternalDiagnostic((CFMutableArrayRef)*outDiagnostics, mainSource, CCDiagnosticLevelError, CFSTR("Swift frontend returned a failure status without emitting diagnostics or captured output."));
        }
        if(frontendOutput != nullptr) { CFRelease(frontendOutput); }
    }

    if(capturedStdout != nullptr) { CFRelease(capturedStdout); }
    if(capturedStderr != nullptr) { CFRelease(capturedStderr); }

    if(outMainSource == nullptr)
    {
        CFRelease(mainSource);
    }
    else
    {
        *outMainSource = mainSource;
    }
    
    return status == 0;
}
