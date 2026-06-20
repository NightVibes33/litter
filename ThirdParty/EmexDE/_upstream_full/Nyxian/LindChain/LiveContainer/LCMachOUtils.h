/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2023 - 2026 LiveContainer
 Copyright (C) 2026 emexlab

 This file is part of LiveContainer.

 LiveContainer is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 LiveContainer is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#ifndef LIVECONTAINER_LCMACHOUTILS_H
#define LIVECONTAINER_LCMACHOUTILS_H

#import <Foundation/Foundation.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach-o/dyld.h>
#import <mach-o/dyld_images.h>
#import <mach-o/ldsyms.h>

typedef struct {
    int fd;
    bool ro;
    char *path;
    void *map;
    size_t size;
    struct mach_header_64 *header;
} LCMachO;

LCMachO *LCMapMachO(const char *path, bool readOnly);
void LCUnmapMachO(LCMachO *machO);

void LCPatchAppBundleFixupARM64eSlice(NSBundle *bundle);
bool LCPatchExecSlice(LCMachO *machO);
uint64_t LCFindSymbolOffsetUnsafe(const char *basePath, const char *symbol);
uint64_t LCFindSymbolOffset(const char *basePath, const char *symbol);
struct mach_header_64 *LCGetLoadedImageHeader(int i0, const char* name);
bool LCCheckCodeSignature(LCMachO *machO);
void *getDyldBase(void);

#endif /* LIVECONTAINER_LCMACHOUTILS_H */
