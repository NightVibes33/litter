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

#import <Foundation/Foundation.h>
#import <LindChain/ProcEnvironment/environment.h>
#import <LindChain/ProcEnvironment/syscall.h>
#import <LindChain/ProcEnvironment/proxy.h>
#import <LindChain/ProcEnvironment/libproc.h>
#import <LindChain/litehook/litehook.h>
#import <LindChain/LiveContainer/Tweaks/libproc.h>
#import <LindChain/ProcEnvironment/Surface/surface.h>
#import <LindChain/ProcEnvironment/Surface/proc/proc.h>

DEFINE_HOOK(proc_listallpids, int, (void *buffer,
                                    int buffersize))
{
    if(buffersize < 0)
    {
        errno = EINVAL;
        return -1;
    }
    
    kinfo_proc_t kp[PROC_MAX];
    uint32_t len = sizeof(kp);
    
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    environment_syscall(SYS_sysctl, mib, 3, &kp, &len);
    
    size_t count = (uint32_t)(len / sizeof(kinfo_proc_t));
    
    size_t n = 0;
    size_t needed_bytes = 0;
    
    needed_bytes = (size_t)count * sizeof(pid_t);
    
    if(buffer != NULL && buffersize > 0)
    {
        size_t capacity = (size_t)buffersize / sizeof(pid_t);
        n = count < capacity ? count : capacity;
        
        pid_t *pids = (pid_t *)buffer;
        
        for(size_t i = 0; i < n; i++)
        {
            pids[i] = kp[i].kp_proc.p_pid;
        }
    }
    
    if(buffer == NULL || buffersize == 0)
    {
        return (int)needed_bytes;
    }
    
    return (int)(n * sizeof(pid_t));
}

DEFINE_HOOK(proc_name, int, (pid_t pid,
                             void *buffer,
                             uint32_t buffersize))
{
    if(buffersize == 0 || buffer == NULL)
    {
        return 0;
    }

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid };
    kinfo_proc_t kp;
    size_t olen = sizeof(kp);
    int64_t retval = environment_syscall(SYS_sysctl, mib, 4, &kp, &olen, NULL, 0);
    if(retval != 0 || olen < sizeof(kp))
    {
        return (int)retval;
    }

    size_t full_len = strlen(kp.kp_proc.p_comm);
    size_t copy_len = (full_len >= buffersize) ? buffersize - 1 : full_len;

    strlcpy((char*)buffer, kp.kp_proc.p_comm, buffersize);
    return (int)copy_len;
}

DEFINE_HOOK(proc_pidpath, int, (pid_t pid,
                                void *buffer,
                                uint32_t buffersize))
{
    /* sanity check */
    if(buffersize == 0 || buffer == NULL)
    {
        return 0;
    }
    
    /* syscall with SYS_PROCPATH */
    int64_t retval = environment_syscall(SYS_procpath, pid, buffer, &buffersize);
    if(retval != 0)
    {
        return 0;
    }
    
    /* final return of lenght */
    return (int)strlen((char*)buffer);
}

/*int proc_libproc_pidinfo(pid_t pid,
                         int flavor,
                         uint64_t arg,
                         void * buffer,
                         int buffersize)
{
    if(buffer == NULL || buffersize <= 0)
    {
        return 0;
    }
    
    ksurface_proc_t proc = {};
    ksurface_error_t error = proc_for_pid(pid, &proc);
    if(error != kSurfaceErrorSuccess)
    {
        return 0;
    }

    switch(flavor)
    {
        case PROC_PIDTASKINFO:
            memset(buffer, 0, buffersize);
            return sizeof(struct proc_taskinfo);
        case PROC_PIDTASKALLINFO: {
            if(buffersize < sizeof(struct proc_taskallinfo))
            {
                return 0;
            }
            struct proc_taskallinfo *info = (struct proc_taskallinfo*)buffer;
            memset(info, 0, sizeof(*info));
            memcpy(&info->pbsd, &proc.bsd, sizeof(proc.bsd) < sizeof(info->pbsd) ? sizeof(proc.bsd) : sizeof(info->pbsd));
            return sizeof(struct proc_taskallinfo);
    }

    default:
        errno = ENOTSUP;
        return 0;
    }
}*/

DEFINE_HOOK(kill, int, (pid_t pid, int sig))
{
    return (int)environment_syscall(SYS_kill, pid, sig);
}

DEFINE_HOOK(raise, int, (int sig))
{
    return HOOK_FUNC(kill)(getpid(), sig);
}

void environment_libproc_init(void)
{
    DO_HOOK_GLOBAL(proc_listallpids);
    DO_HOOK_GLOBAL(proc_name);
    DO_HOOK_GLOBAL(proc_pidpath);
    DO_HOOK_GLOBAL(kill);
    DO_HOOK_GLOBAL(raise);
}
