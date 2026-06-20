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

#import <MobileDevelopmentKit/MDKOSVersion.h>
#import <UIKit/UIKit.h>

uint32_t MDKVersionStringToNumeric(NSString *versionString)
{
    NSArray<NSString*> *parts = [versionString componentsSeparatedByString:@"."];
    int(^parseInteger)(NSString *) = ^int(NSString *str) {
        if(str.length == 0)
        {
            @throw [NSException exceptionWithName:@"MDKVersionStringConversionError" reason:@"String is empty" userInfo:nil];
        }
        
        /* remove whitespaces */
        NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        /* applying strict integer validation */
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger value = 0;
        
        /* look for integer */
        if([scanner scanInteger:&value] && scanner.scanLocation == trimmed.length)
        {
            return (int)value;
        }
        
        @throw [NSException exceptionWithName:@"MDKVersionStringConversionError" reason:@"Not a integer" userInfo:nil];
    };
    
    @try {
        int major = parts.count > 0 ? (int)parseInteger(parts[0]) : 0;
        int minor = parts.count > 1 ? (int)parseInteger(parts[1]) : 0;
        int patch = parts.count > 2 ? (int)parseInteger(parts[2]) : 0;
        return major * 1000000 + minor * 1000 + patch;
    } @catch(id ex) {
        return MDKOSNumericVersionConversionFailed;
    }
}

@implementation MDKOSVersion

+ (instancetype)hostVersion
{
    static MDKOSVersion *version = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        version = [[self alloc] init];
    });
    return version;
}

+ (instancetype)iPadOSFirstVersion
{
    static MDKOSVersion *version = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        version = [[self alloc] initWithVersionString:@"13.0"];
    });
    return version;
}

+ (instancetype)versionWithVersionString:(NSString *)versionString
{
    return [[self alloc] initWithVersionString:versionString];
}

- (instancetype)init
{
    return [self initWithVersionString:UIDevice.currentDevice.systemVersion];
}

- (instancetype)initWithVersionString:(NSString *)versionString
{
    self = [super init];
    _versionString = (versionString == nil) ? @"9.0" : [versionString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _versionNumeric = MDKVersionStringToNumeric(_versionString);
    return (_versionNumeric == MDKOSNumericVersionConversionFailed) ? nil : self;
}

- (BOOL)isEqual:(MDKOSVersion*)version
{
    return self.versionNumeric == version.versionNumeric;
}

- (NSString*)description
{
    NSString *system = @"UnknownDarwin";
    switch(UIDevice.currentDevice.userInterfaceIdiom)
    {
        case UIUserInterfaceIdiomPhone:
            system = @"iOS";
            break;
        case UIUserInterfaceIdiomPad:
            if(MDKOSVersion.iPadOSFirstVersion.versionNumeric <= self.versionNumeric)
            {
                system = @"iPadOS";
            }
            else
            {
                system = @"iOS";
            }
            break;
        case UIUserInterfaceIdiomTV:
            system = @"tvOS";
            break;
        case UIUserInterfaceIdiomMac:
            system = NSProcessInfo.processInfo.isiOSAppOnMac ? @"iOS-on-macOS" : @"macOS";
            break;
        case UIUserInterfaceIdiomVision: /* live inside of your code, hahaha */
            system = @"visionOS";
            break;
        case UIUserInterfaceIdiomCarPlay:
            system = @"CarPlay";
            break;
        default:
            break;
    }
    return [system stringByAppendingFormat:@" %@", self.versionString];
}

@end
