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

#ifndef MDKOSVERSION_H
#define MDKOSVERSION_H

#import <Foundation/Foundation.h>

#define MDKOSNumericVersionConversionFailed 0xFFFFFFFF

uint32_t MDKVersionStringToNumeric(NSString * _Nonnull versionString);

@interface MDKOSVersion : NSObject

@property (nonatomic, strong, readonly, nonnull) NSString *versionString;
@property (nonatomic, readonly) uint32_t versionNumeric;

@property (class, nonatomic, strong, readonly, nonnull) MDKOSVersion *hostVersion;
@property (class, nonatomic, strong, readonly, nonnull) MDKOSVersion *iPadOSFirstVersion;

+ (instancetype _Nullable)versionWithVersionString:(NSString * _Nullable)versionString;

- (instancetype _Nonnull)init;
- (instancetype _Nullable)initWithVersionString:(NSString * _Nullable)versionString;

- (BOOL)isEqual:(MDKOSVersion * _Nonnull)version;
- (NSString*)description;

@end

#endif /* MDKOSVERSION_H */
