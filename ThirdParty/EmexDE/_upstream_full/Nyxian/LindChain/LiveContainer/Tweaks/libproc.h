/*
 * Copyright (c) 2006, 2007 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */
#ifndef _LIBPROC_H_
#define _LIBPROC_H_

#include <sys/cdefs.h>
#include <sys/param.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <stdint.h>

#include <LindChain/LiveContainer/Tweaks/proc_info.h>

#ifndef PROC_PIDTASKINFO
#define PROC_PIDTASKINFO     4
#endif
#ifndef PROC_PIDTASKALLINFO
#define PROC_PIDTASKALLINFO  2
#endif

struct proc_taskinfo {
    uint64_t        pti_virtual_size;
    uint64_t        pti_resident_size;
    uint64_t        pti_total_user;
    uint64_t        pti_total_system;
    uint64_t        pti_threads_user;
    uint64_t        pti_threads_system;
    int32_t         pti_policy;
    int32_t         pti_faults;
    int32_t         pti_pageins;
    int32_t         pti_cow_faults;
    int32_t         pti_messages_sent;
    int32_t         pti_messages_received;
    int32_t         pti_syscalls_mach;
    int32_t         pti_syscalls_unix;
    int32_t         pti_csw;
    int32_t         pti_threadnum;
    int32_t         pti_numrunning;
    int32_t         pti_priority;
};

struct proc_bsdinfo {
    uint32_t        pbi_flags;        /* 64bit; emulated etc */
    uint32_t        pbi_status;
    uint32_t        pbi_xstatus;
    uint32_t        pbi_pid;
    uint32_t        pbi_ppid;
    uid_t            pbi_uid;
    gid_t            pbi_gid;
    uid_t            pbi_ruid;
    gid_t            pbi_rgid;
    uid_t            pbi_svuid;
    gid_t            pbi_svgid;
    uint32_t        rfu_1;            /* reserved */
    char            pbi_comm[MAXCOMLEN];
    char            pbi_name[2*MAXCOMLEN];    /* empty if no name is registered */
    uint32_t        pbi_nfiles;
    uint32_t        pbi_pgid;
    uint32_t        pbi_pjobc;
    uint32_t        e_tdev;            /* controlling tty dev */
    uint32_t        e_tpgid;        /* tty process group id */
    int32_t            pbi_nice;
    uint64_t        pbi_start_tvsec;
    uint64_t        pbi_start_tvusec;
};

struct proc_taskallinfo {
    struct proc_bsdinfo   pbsd;
    struct proc_taskinfo  ptinfo;
};

/*
 * This header file contains private interfaces to obtain process information.
 * These interfaces are subject to change in future releases.
 */

/*!
    @define PROC_LISTPIDSPATH_PATH_IS_VOLUME
    @discussion This flag indicates that all processes that hold open
        file references on the volume associated with the specified
        path should be returned.
 */
#define PROC_LISTPIDSPATH_PATH_IS_VOLUME    1


/*!
    @define PROC_LISTPIDSPATH_EXCLUDE_EVTONLY
    @discussion This flag indicates that file references that were opened
        with the O_EVTONLY flag should be excluded from the matching
        criteria.
 */
#define PROC_LISTPIDSPATH_EXCLUDE_EVTONLY    2

__BEGIN_DECLS

int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
int proc_listallpids(void * buffer, int buffersize);
int proc_listpidspath(uint32_t    type, uint32_t    typeinfo, const char    *path, uint32_t    pathflags, void        *buffer, int        buffersize);
int proc_pidinfo(int pid, int flavor, uint64_t arg,  void *buffer, int buffersize);
int proc_pidfdinfo(int pid, int fd, int flavor, void * buffer, int buffersize);
int proc_name(int pid, void * buffer, uint32_t buffersize);
int proc_regionfilename(int pid, uint64_t address, void * buffer, uint32_t buffersize);
int proc_kmsgbuf(void * buffer, uint32_t buffersize);
int proc_pidpath(int pid, void * buffer, uint32_t  buffersize);
int proc_libversion(int *major, int * minor);
int proc_pid_rusage(int pid, int flavor, struct rusage_info_v2 *rusage);
/*
 * A process can use the following api to set its own process control
 * state on resoure starvation. The argument can have one of the PROC_SETPC_XX values
 */
#define PROC_SETPC_NONE        0
#define PROC_SETPC_THROTTLEMEM    1
#define PROC_SETPC_SUSPEND    2
#define PROC_SETPC_TERMINATE    3

int proc_setpcontrol(const int control);
__END_DECLS

#endif /*_LIBPROC_H_ */
