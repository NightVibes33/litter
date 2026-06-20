/*
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

#import <MobileDevelopmentKit/MDKSDK.h>
#import <CoreCompiler/CCSDK.h>

@implementation MDKSDK

+ (void)load
{
    _CFRuntimeBridgeClasses(CCSDKGetTypeID(), "MDKSDK");
}

+ (instancetype _Nullable)sdkForDirectoryURL:(NSURL * _Nonnull)directoryURL
{
    return (__bridge_transfer MDKSDK*)CCSDKCreateWithDirectoryURL(kCFAllocatorSystemDefault, (__bridge CFURLRef)directoryURL);
}

- (NSURL*)directoryURL
{
    return (__bridge NSURL*)CCSDKGetDirectoryURL((__bridge CCSDKRef)self);
}

- (MDKOSVersion*)version
{
    NSString *versionString = (__bridge_transfer NSString*)CCSDKCopyVersion((__bridge CCSDKRef)self);
    return [MDKOSVersion versionWithVersionString:versionString];
}

- (NSArray<MDKOSVersion*>*)supportedVersions
{
    NSURL *settingsURL = [self.directoryURL URLByAppendingPathComponent:@"SDKSettings.plist"];
    NSDictionary *settingsDictionary = [NSDictionary dictionaryWithContentsOfURL:settingsURL];
    if(settingsDictionary != nil)
    {
        NSArray<NSString*> *validDeploymentTargets = nil;
        
        NSDictionary *supportedTargetsDictionary = settingsDictionary[@"SupportedTargets"];
        if(supportedTargetsDictionary != nil)
        {
            /*
             * this is a modern apple SDK, from now on
             * we already know that the legacy path is
             * not working if this doesn't.
             */
            NSDictionary *platformDictionary = supportedTargetsDictionary[@"iphoneos"];
            if(platformDictionary == nil)
            {
                goto failed;
            }
            
            validDeploymentTargets = platformDictionary[@"ValidDeploymentTargets"];
        }
        else
        {
            /*
             * must be a legacy SDK, usually not shipped
             * on Nyxian, weird. Maybe someone using MDK
             * in a 3rd party IDE x3 Thank you for your
             * support!
             */
            validDeploymentTargets = settingsDictionary[@"ValidDeploymentTargets"];
        }
        
        if(validDeploymentTargets == nil)
        {
            goto failed;
        }
        
        NSMutableArray *validMDKOSVersionDeploymentTargets = [NSMutableArray arrayWithCapacity:[validDeploymentTargets count]];
        if(validMDKOSVersionDeploymentTargets == nil)
        {
            goto failed;
        }
        
        for(NSString *deploymentTarget in validDeploymentTargets)
        {
            MDKOSVersion *osVersion = [MDKOSVersion versionWithVersionString:deploymentTarget];
            if(osVersion != nil)
            {
                [validMDKOSVersionDeploymentTargets addObject:osVersion];
            }
        }
        return validMDKOSVersionDeploymentTargets;
    }
    
failed:
    return @[[MDKOSVersion versionWithVersionString:@"26.5"]];
}

@end
