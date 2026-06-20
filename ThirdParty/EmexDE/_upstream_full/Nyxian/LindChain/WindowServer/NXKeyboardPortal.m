/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import <LindChain/WindowServer/NXKeyboardPortal.h>

@implementation NXKeyboardPortal

- (instancetype)initWithFrame:(CGRect)frame
               fileDescriptor:(int)fd
             windowIdentifier:(id_t)wid
{
    self = [super initWithFrame:frame];
    _clientFd = fd;
    _clientWid = wid;
    return self;
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)hasText
{
    return YES;
}

- (void)insertText:(NSString *)text
{
    if(self.clientFd < 0)
    {
        return;
    }
    
    if([text isEqualToString:@"\n"])
    {
        const char *nl = "\n";
        write(self.clientFd, nl, strlen(nl));
        return;
    }
    
    const char *buffer = [text cStringUsingEncoding:NSUTF8StringEncoding];
    if(buffer)
    {
        write(self.clientFd, buffer, strlen(buffer));
    }
}

- (void)deleteBackward
{
    if(self.clientFd < 0)
    {
        return;
    }
    char backspace = 0x08;
    write(self.clientFd, &backspace, 1);
}

- (BOOL)resignFirstResponder
{
    BOOL didResign = [super resignFirstResponder];
    if(didResign)
    {
        char unfocus = 0x00;
        write(self.clientFd, &unfocus, 1);
    }
    
    return didResign;
}

- (void)dealloc
{
    if(_clientFd >= 0)
    {
        close(_clientFd);
    }
}

@end
