#!/usr/bin/env python3
# Patch emexDE CoreCompiler sources for the public unsigned iOS CI build.
#
# The emexDE release ships iOS LLVM/Swift support dylibs but not the exact
# generated Swift compiler headers needed to compile the embedded Swift frontend
# source in a fresh GitHub runner. Keep upstream sources in the repository, then
# replace only that frontend path in CI so the app can build and the rest of
# emexDE remains linked into Litter.
from __future__ import annotations

import argparse
from pathlib import Path


CCDRIVER_CPP = r'''/*
 * MIT License
 *
 * Copyright (c) 2026 emexlab
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

#include <CoreCompiler/CCDriver.h>
#include <CoreCompiler/CCUtils.h>
#include <CoreCompiler/CCUtilsPrivate.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/DiagnosticOptions.h>
#include <clang/Driver/Action.h>
#include <clang/Driver/Compilation.h>
#include <clang/Driver/Driver.h>
#include <clang/Driver/Job.h>
#include <llvm/Option/ArgList.h>
#include <llvm/ADT/SmallPtrSet.h>
#include <llvm/ADT/StringMap.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Casting.h>
#include <llvm/Support/VirtualFileSystem.h>
#include <algorithm>
#include <cassert>
#include <memory>
#include <new>
#include <string>

using namespace llvm;
using namespace llvm::opt;

static CFTypeID gCCDriverTypeID = _kCFRuntimeNotATypeID;

struct opaque_ccdriver {
    CFRuntimeBase _base;
    CCDriverType type;

    IntrusiveRefCntPtr<clang::DiagnosticsEngine> clangDiagnosticEngine;
    std::unique_ptr<clang::driver::Driver> clangDriver;
    std::unique_ptr<clang::driver::Compilation> clangCompilation;

    void *outputPathCallbackContext;
    CCOutputPathCallback callback;
    llvm::SmallVector<std::string, 64> argStorage;
    llvm::SmallVector<const char *, 64> argPtr;
};

static CFTypeRef CCDriverCopy(CFAllocatorRef allocator, CFTypeRef cf)
{
    return CFRetain(cf);
}

static void CCDriverInit(CFTypeRef cf)
{
    CCDriverRef driverRef = (CCDriverRef)cf;
    new (&driverRef->clangDiagnosticEngine) IntrusiveRefCntPtr<clang::DiagnosticsEngine>();
    new (&driverRef->clangDriver) std::unique_ptr<clang::driver::Driver>();
    new (&driverRef->clangCompilation) std::unique_ptr<clang::driver::Compilation>();
    new (&driverRef->argStorage) llvm::SmallVector<std::string, 64>();
    new (&driverRef->argPtr) llvm::SmallVector<const char *, 64>();
    driverRef->type = CCDriverTypeClang;
    driverRef->outputPathCallbackContext = nullptr;
    driverRef->callback = nullptr;
}

static void CCDriverFinalize(CFTypeRef cf)
{
    CCDriverRef driverRef = (CCDriverRef)cf;
    std::destroy_at(&driverRef->clangCompilation);
    std::destroy_at(&driverRef->clangDriver);
    std::destroy_at(&driverRef->clangDiagnosticEngine);
    std::destroy_at(&driverRef->argPtr);
    std::destroy_at(&driverRef->argStorage);
}

static const CFRuntimeClass gCCDriverClass = {
    0,
    "CCDriver",
    CCDriverInit,
    CCDriverCopy,
    CCDriverFinalize,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    0
};

CFTypeID CCDriverGetTypeID(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gCCDriverTypeID = _CFRuntimeRegisterClass(&gCCDriverClass);
    });
    return gCCDriverTypeID;
}

CCDriverRef CCDriverCreate(CFAllocatorRef allocator, CFArrayRef arguments, CCDriverType type)
{
    assert(arguments != nullptr);

    CCDriverRef driverRef = (CCDriverRef)_CFRuntimeCreateInstance(allocator, CCDriverGetTypeID(), sizeof(struct opaque_ccdriver) - sizeof(CFRuntimeBase), NULL);
    if(!driverRef)
    {
        return nullptr;
    }

    driverRef->type = type;
    driverRef->argStorage = CCArrayToStringVector(arguments);

    if(type == CCDriverTypeClang)
    {
        driverRef->argStorage.insert(driverRef->argStorage.begin(), "-fuse-ld=lld");
        driverRef->argStorage.insert(driverRef->argStorage.begin(), "clang");
    }
    else if(type == CCDriverTypeSwift)
    {
        driverRef->argStorage.insert(driverRef->argStorage.begin(), "swiftc");
    }
    else
    {
        CFRelease(driverRef);
        return nullptr;
    }

    driverRef->argPtr.clear();
    for(const std::string &arg : driverRef->argStorage)
    {
        driverRef->argPtr.push_back(arg.c_str());
    }

    if(type == CCDriverTypeClang)
    {
        IntrusiveRefCntPtr<clang::DiagnosticIDs> DiagID(new clang::DiagnosticIDs());
        IntrusiveRefCntPtr<clang::DiagnosticOptions> DiagOpts(new clang::DiagnosticOptions());
        driverRef->clangDiagnosticEngine = IntrusiveRefCntPtr<clang::DiagnosticsEngine>(new clang::DiagnosticsEngine(DiagID, DiagOpts, new clang::IgnoringDiagConsumer(), true));

        try
        {
            driverRef->clangDriver = std::make_unique<clang::driver::Driver>("clang", "", *driverRef->clangDiagnosticEngine);
        }
        catch (...)
        {
            CFRelease(driverRef);
            return nullptr;
        }
    }

    return driverRef;
}

static CCJobType _CCJobTypeGetFromClangCommand(const clang::driver::Command *Cmd)
{
    const clang::driver::Action &source = Cmd->getSource();

    if(clang::isa<clang::driver::CompileJobAction>(source) ||
       clang::isa<clang::driver::AssembleJobAction>(source))
    {
        return CCJobTypeCompiler;
    }
    if(clang::isa<clang::driver::LinkJobAction>(source))
    {
        return CCJobTypeLinker;
    }
    return CCJobTypeUnknown;
}

static std::string _CCStringToStd(CFStringRef s)
{
    if(const char *fast = CFStringGetCStringPtr(s, kCFStringEncodingUTF8))
    {
        return std::string(fast);
    }
    CFIndex len = CFStringGetLength(s);
    CFIndex max = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
    std::string out;
    out.resize(max);
    CFIndex used = 0;
    CFStringGetBytes(s, CFRangeMake(0, len), kCFStringEncodingUTF8, 0, false, (UInt8 *)out.data(), max, &used);
    out.resize(used);
    return out;
}

static void _AppendCStr(CFMutableArrayRef arr, CFAllocatorRef a, const char *str)
{
    if(CFStringRef s = CFStringCreateWithCString(a, str, kCFStringEncodingUTF8))
    {
        CFArrayAppendValue(arr, s);
        CFRelease(s);
    }
}

static void _AppendJob(CFMutableArrayRef out, CFAllocatorRef a, CCJobType type, const llvm::opt::ArgStringList &argv)
{
    CFMutableArrayRef argsArray = CFArrayCreateMutable(a, argv.size(), &kCFTypeArrayCallBacks);
    for(const char *arg : argv)
    {
        if(arg)
        {
            _AppendCStr(argsArray, a, arg);
        }
    }
    CCJobRef jobRef = CCJobCreate(a, type, argsArray);
    CFRelease(argsArray);
    if(jobRef)
    {
        CFArrayAppendValue(out, jobRef);
        CFRelease(jobRef);
    }
}

static Boolean IsDriverInputArg(CFStringRef arg)
{
    static const CFStringRef kInputSuffixes[] = {
        CFSTR(".c"), CFSTR(".cc"), CFSTR(".cpp"), CFSTR(".cxx"),
        CFSTR(".m"), CFSTR(".mm"), CFSTR(".S"), CFSTR(".s"),
    };
    for(size_t i = 0; i < sizeof(kInputSuffixes) / sizeof(*kInputSuffixes); i++)
    {
        if(CFStringHasSuffix(arg, kInputSuffixes[i]))
        {
            return true;
        }
    }
    return false;
}

static void CollapseArgsToWl(CFMutableArrayRef argsArray)
{
    CFIndex count = CFArrayGetCount(argsArray);
    if(count == 0)
    {
        return;
    }

    CFMutableArrayRef passthrough = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFMutableStringRef wl = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringAppend(wl, CFSTR("-Wl"));
    Boolean haveWlPayload = false;

    for(CFIndex i = 0; i < count; i++)
    {
        CFStringRef arg = (CFStringRef)CFArrayGetValueAtIndex(argsArray, i);

        if(CFEqual(arg, CFSTR("-o")))
        {
            CFArrayAppendValue(passthrough, arg);
            if(i + 1 < count)
            {
                CFArrayAppendValue(passthrough, CFArrayGetValueAtIndex(argsArray, i + 1));
                i++;
            }
            continue;
        }

        if(IsDriverInputArg(arg))
        {
            CFArrayAppendValue(passthrough, arg);
            continue;
        }

        CFStringAppend(wl, CFSTR(","));
        CFStringAppend(wl, arg);
        haveWlPayload = true;
    }

    CFArrayRemoveAllValues(argsArray);
    if(haveWlPayload)
    {
        CFArrayAppendValue(argsArray, wl);
    }
    CFArrayAppendArray(argsArray, passthrough, CFRangeMake(0, CFArrayGetCount(passthrough)));

    CFRelease(wl);
    CFRelease(passthrough);
}

CFArrayRef CCDriverCreateJobs(CCDriverRef driver)
{
    CFAllocatorRef allocator = CFGetAllocator(driver);
    CFMutableArrayRef jobsArray = CFArrayCreateMutable(allocator, 0, &kCFTypeArrayCallBacks);

    if(driver->type == CCDriverTypeSwift)
    {
        llvm::opt::ArgStringList swiftArgs;
        for(size_t i = 1; i < driver->argPtr.size(); ++i)
        {
            swiftArgs.push_back(driver->argPtr[i]);
        }
        _AppendJob(jobsArray, allocator, CCJobTypeSwiftCompiler, swiftArgs);
        return jobsArray;
    }

    if(driver->type != CCDriverTypeClang)
    {
        CFRelease(jobsArray);
        return nullptr;
    }

    using namespace clang::driver;
    using llvm::cast;
    using llvm::dyn_cast;
    using llvm::isa;

    driver->clangCompilation.reset(driver->clangDriver->BuildCompilation(driver->argPtr));
    if(!driver->clangCompilation)
    {
        CFRelease(jobsArray);
        return nullptr;
    }

    llvm::StringMap<const char *> pathRemap;
    llvm::SmallPtrSet<const Command *, 8> skippedJobs;

    if(driver->callback)
    {
        for(auto &Job : driver->clangCompilation->getJobs())
        {
            if(!isa<Command>(Job))
            {
                continue;
            }

            Command &Cmd = const_cast<Command &>(cast<Command>(Job));
            const clang::driver::Action &Src = Cmd.getSource();
            if(!isa<CompileJobAction>(Src) && !isa<AssembleJobAction>(Src))
            {
                continue;
            }

            const clang::driver::Action *leaf = &Src;
            while(!leaf->getInputs().empty())
            {
                leaf = leaf->getInputs()[0];
            }

            const char *baseInput = nullptr;
            if(auto *IA = dyn_cast<InputAction>(leaf))
            {
                baseInput = IA->getInputArg().getValue();
            }

            bool skip = false;
            CFStringRef newCF = driver->callback(baseInput, &skip, driver->outputPathCallbackContext);
            if(!newCF)
            {
                continue;
            }

            std::string s = _CCStringToStd(newCF);
            CFRelease(newCF);

            const char *newArg = driver->clangCompilation->getArgs().MakeArgString(s);

            llvm::opt::ArgStringList newArgs;
            const auto &old = Cmd.getArguments();
            for(size_t i = 0; i < old.size(); ++i)
            {
                if(llvm::StringRef(old[i]) == "-o" && i + 1 < old.size())
                {
                    pathRemap[old[i + 1]] = newArg;
                    newArgs.push_back(old[i]);
                    newArgs.push_back(newArg);
                    ++i;
                }
                else
                {
                    newArgs.push_back(old[i]);
                }
            }
            Cmd.replaceArguments(newArgs);
            if(skip)
            {
                skippedJobs.insert(&Cmd);
            }
        }
    }

    if(!pathRemap.empty())
    {
        for(auto &Job : driver->clangCompilation->getJobs())
        {
            if(!isa<Command>(Job))
            {
                continue;
            }

            Command &Cmd = const_cast<Command &>(cast<Command>(Job));
            if(!isa<LinkJobAction>(Cmd.getSource()))
            {
                continue;
            }

            llvm::opt::ArgStringList newArgs;
            for(const char *a : Cmd.getArguments())
            {
                auto it = pathRemap.find(a);
                newArgs.push_back(it != pathRemap.end() ? it->second : a);
            }

            Cmd.replaceArguments(newArgs);
        }
    }

    for(auto &Job : driver->clangCompilation->getJobs())
    {
        if(!isa<Command>(Job))
        {
            continue;
        }
        const Command &Cmd = cast<Command>(Job);
        if(skippedJobs.contains(&Cmd))
        {
            continue;
        }

        CCJobType type = _CCJobTypeGetFromClangCommand(&Cmd);
        _AppendJob(jobsArray, allocator, type, Cmd.getArguments());
    }

    return jobsArray;
}

void CCDriverSetOutputPathCallback(CCDriverRef driver, CCOutputPathCallback callback, void *context)
{
    driver->callback = callback;
    driver->outputPathCallbackContext = context;
}

void *CCDriverGetOutputPathCallbackContext(CCDriverRef driver)
{
    return driver->outputPathCallbackContext;
}

CFURLRef CCDriverCopySysrootURL(CCDriverRef driver)
{
    std::string cxxstr;

    if(driver->type == CCDriverTypeClang)
    {
        if(!driver->clangCompilation)
        {
            return nullptr;
        }
        cxxstr = driver->clangCompilation->getSysRoot().str();
    }
    else if(driver->type == CCDriverTypeSwift)
    {
        for(size_t i = 0; i + 1 < driver->argStorage.size(); ++i)
        {
            if(driver->argStorage[i] == "-sdk")
            {
                cxxstr = driver->argStorage[i + 1];
                break;
            }
        }
    }
    else
    {
        return nullptr;
    }

    if(cxxstr.empty())
    {
        return nullptr;
    }

    CFAllocatorRef allocator = CFGetAllocator(driver);
    CFStringRef str = CFStringCreateWithCString(allocator, cxxstr.c_str(), kCFStringEncodingUTF8);
    if(!str)
    {
        return nullptr;
    }
    CFURLRef url = CFURLCreateWithFileSystemPath(allocator, str, kCFURLPOSIXPathStyle, true);
    CFRelease(str);
    return url;
}

CCSDKRef CCDriverCopySDK(CCDriverRef driver)
{
    CFURLRef sdkRoot = CCDriverCopySysrootURL(driver);
    if(sdkRoot == nullptr)
    {
        return nullptr;
    }

    CCSDKRef sdk = CCSDKCreateWithFileURL(CFGetAllocator(driver), sdkRoot);
    CFRelease(sdkRoot);
    return sdk;
}
'''


CCSWIFT_COMPILER_CPP = r'''/*
 * MIT License
 *
 * Copyright (c) 2026 Kyle-Ye
 * Copyright (c) 2026 emexlab
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

CC_EXPORT Boolean CCSwiftCompilerJobExecute(CCJobRef job,
                                            CFArrayRef *outDiagnostics,
                                            CFStringRef *outMainSource)
{
    if(outDiagnostics != nullptr)
    {
        *outDiagnostics = CFArrayCreate(kCFAllocatorDefault, nullptr, 0, &kCFTypeArrayCallBacks);
    }

    if(outMainSource != nullptr)
    {
        *outMainSource = CFStringCreateWithCString(kCFAllocatorDefault, "swift", kCFStringEncodingUTF8);
    }

    return false;
}
'''

def replace_or_confirm(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f"Missing expected emexDE CoreCompiler compatibility block: {label}")


def patch(root: Path) -> None:
    cc_root = root / "ThirdParty/EmexDE/Source/CoreCompiler"
    cc_driver = cc_root / "Tools/CCDriver.cpp"
    dependency_scanner = cc_root / "Tools/CCDependencyScanner.cpp"
    cc_compiler = cc_root / "Tools/Compiler/CCCompiler.cpp"
    swift_compiler = cc_root / "Tools/Compiler/CCSwiftCompiler.cpp"
    cc_utils = cc_root / "CCUtils.cpp"

    missing = [p for p in (cc_driver, dependency_scanner, cc_compiler, swift_compiler, cc_utils) if not p.exists()]
    if missing:
        raise SystemExit("Missing emexDE CoreCompiler source files: " + ", ".join(str(p) for p in missing))

    cc_driver.write_text(CCDRIVER_CPP)
    swift_compiler.write_text(CCSWIFT_COMPILER_CPP)

    scanner_text = dependency_scanner.read_text()
    scanner_text = replace_or_confirm(
        scanner_text,
        "new (&dependencyScanner->service) DependencyScanningService(ScanningMode::DependencyDirectivesScan, ScanningOutputFormat::Full, CASOptions{}, /*CAS=*/nullptr, /*Cache=*/nullptr, /*SharedFS=*/nullptr);",
        "new (&dependencyScanner->service) DependencyScanningService(ScanningMode::DependencyDirectivesScan, ScanningOutputFormat::Full);",
        "DependencyScanningService constructor",
    )
    dependency_scanner.write_text(scanner_text)

    compiler_text = cc_compiler.read_text()
    compiler_text = replace_or_confirm(
        compiler_text,
        "auto DiagOpts = std::make_shared<DiagnosticOptions>();\n    IntrusiveRefCntPtr<DiagnosticIDs> DiagID(new DiagnosticIDs());\n    IntrusiveRefCntPtr<DiagnosticsEngine> Diags(new DiagnosticsEngine(DiagID, *DiagOpts, new IgnoringDiagConsumer(), /*ShouldOwnClient=*/true));",
        "IntrusiveRefCntPtr<DiagnosticOptions> DiagOpts(new DiagnosticOptions());\n    IntrusiveRefCntPtr<DiagnosticIDs> DiagID(new DiagnosticIDs());\n    IntrusiveRefCntPtr<DiagnosticsEngine> Diags(new DiagnosticsEngine(DiagID, DiagOpts, new IgnoringDiagConsumer(), /*ShouldOwnClient=*/true));",
        "DiagnosticsEngine ownership",
    )
    compiler_text = replace_or_confirm(
        compiler_text,
        "CI,\n        std::make_shared<PCHContainerOperations>(),\n        DiagOpts,\n        Diags,\n        Act.release(),",
        "CI,\n        std::make_shared<PCHContainerOperations>(),\n        Diags,\n        Act.release(),",
        "ASTUnit diagnostics argument",
    )
    cc_compiler.write_text(compiler_text)

    utils_text = cc_utils.read_text()
    utils_text = utils_text.replace("#include <swift/Basic/InitializeSwiftModules.h>\n", "")
    cc_utils.write_text(utils_text)

    print("Patched emexDE CoreCompiler for unsigned iOS CI:")
    print(f"  {cc_driver}")
    print(f"  {dependency_scanner} (normalized dependency scanner constructor)")
    print(f"  {cc_compiler} (normalized Clang diagnostics ownership)")
    print(f"  {swift_compiler}")
    print(f"  {cc_utils} (removed unused Swift compiler header include)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".", help="Repository root")
    args = parser.parse_args()
    patch(Path(args.root).resolve())


if __name__ == "__main__":
    main()
