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

#import <sys/socket.h>

#import <UIKit/UIKit.h>

#import <LindChain/ProcEnvironment/kbdportal.h>
#import <LindChain/ProcEnvironment/syscall.h>
#import <LindChain/Utils/Swizzle.h>

#import <pthread.h>

/* MARK: THIS IS A EXPERIMENTAL FIX FOR THE IOS27 KEYBOARD ISSUE */

static int gWriteFD = -1;
static int gReadFD = -1;
static pthread_t gThread;
static __weak id<UITextInput> gActiveInput;
static volatile bool gRunning = false;

void *ReaderThread(void *arg)
{
    char buf[1024];

    while(gRunning)
    {
        ssize_t n = read(gReadFD, buf, sizeof(buf));
        if(n <= 0)
        {
            break;
        }

        ssize_t startIdx = 0;
        for(ssize_t i = 0; i < n; i++)
        {
            char c = buf[i];
            
            if(c == 0x00)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [(UIResponder*)gActiveInput resignFirstResponder];
                });
            }
            if(c == 0x08 || c == 0x7F)
            {
                if(i > startIdx)
                {
                    size_t len = i - startIdx;
                    NSString *text = [[NSString alloc] initWithBytes:&buf[startIdx] length:len encoding:NSUTF8StringEncoding];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        id<UITextInput> input = gActiveInput;
                        UITextRange *range = input.selectedTextRange;
                        if(range)
                        {
                            [input replaceRange:range withText:text];
                        }
                    });
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [(id<UITextInput>)gActiveInput deleteBackward];
                });
                
                startIdx = i + 1;
            }
        }
        
        if(startIdx < n)
        {
            size_t len = n - startIdx;
            NSString *text = [[NSString alloc] initWithBytes:&buf[startIdx] length:len encoding:NSUTF8StringEncoding];
            dispatch_async(dispatch_get_main_queue(), ^{
                id<UITextInput> input = gActiveInput;
                UITextRange *range = input.selectedTextRange;
                if(range)
                {
                    [input replaceRange:range withText:text];
                }
            });
        }
    }

    return NULL;
}

void StartInputPipe(id<UITextInput> input)
{
    int fds[2];
    if(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0)
    {
        return;
    }

    gReadFD = fds[0];
    gWriteFD = fds[1];
    
    int set = 1;
    setsockopt(gWriteFD, SOL_SOCKET, SO_NOSIGPIPE, &set, sizeof(set));
    setsockopt(gReadFD, SOL_SOCKET, SO_NOSIGPIPE, &set, sizeof(set));
    environment_syscall(SYS_kbdctl, gWriteFD);

    gActiveInput = input;
    gRunning = true;

    pthread_create(&gThread, NULL, ReaderThread, NULL);
}

void StopInputPipe(void)
{
    gRunning = false;

    if(gReadFD != -1)
    {
        shutdown(gReadFD, SHUT_RDWR);
        close(gReadFD);
    }

    if(gWriteFD != -1)
    {
        shutdown(gWriteFD, SHUT_RDWR);
        close(gWriteFD);
    }

    pthread_join(gThread, NULL);

    gReadFD = -1;
    gWriteFD = -1;
    gActiveInput = nil;
    
    environment_syscall(SYS_kbdctl, -1);
}

@implementation UIResponder (ProcEnvironment)

- (BOOL)hook_becomeFirstResponder
{
    BOOL didBecame = [self hook_becomeFirstResponder];
    
    if(didBecame && [self conformsToProtocol:@protocol(UITextInput)])
    {
        StartInputPipe((id<UITextInput>)self);
    }

    return didBecame;
}

- (BOOL)hook_resignFirstResponder
{
    BOOL didResign = [self hook_resignFirstResponder];

    if(didResign && (id)self == gActiveInput)
    {
        StopInputPipe();
    }

    return didResign;
}

@end

void environment_kbdportal_init(void)
{
    if(@available(iOS 27.0, *))
    {
        swizzle_objc_method(@selector(becomeFirstResponder), [UIResponder class], @selector(hook_becomeFirstResponder), nil);
        swizzle_objc_method(@selector(resignFirstResponder), [UIResponder class], @selector(hook_resignFirstResponder), nil);
    }
}
