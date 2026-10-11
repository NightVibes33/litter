//! Darwin routing constants from Apple XNU bsd/net/route.h.
//! libc 0.2.190 exports these only on macOS; iOS shares the wire ABI.

use libc::c_int;

pub const RTAX_BRD: c_int = 7;
pub const RTAX_DST: c_int = 0;
pub const RTAX_GATEWAY: c_int = 1;
pub const RTAX_IFP: c_int = 4;
pub const RTAX_MAX: c_int = 8;
pub const RTAX_NETMASK: c_int = 2;
pub const RTA_BRD: c_int = 0x80;
pub const RTA_DST: c_int = 0x1;
pub const RTA_GATEWAY: c_int = 0x2;
pub const RTA_IFA: c_int = 0x20;
pub const RTA_IFP: c_int = 0x10;
pub const RTA_NETMASK: c_int = 0x4;
pub const RTF_GATEWAY: c_int = 0x2;
pub const RTF_IFSCOPE: c_int = 0x1000000;
pub const RTM_ADD: c_int = 0x1;
pub const RTM_CHANGE: c_int = 0x3;
pub const RTM_DELADDR: c_int = 0xd;
pub const RTM_DELETE: c_int = 0x2;
pub const RTM_DELMADDR: c_int = 0x10;
pub const RTM_GET: c_int = 0x4;
pub const RTM_GET2: c_int = 0x14;
pub const RTM_IFINFO: c_int = 0xe;
pub const RTM_IFINFO2: c_int = 0x12;
pub const RTM_LOCK: c_int = 0x8;
pub const RTM_LOSING: c_int = 0x5;
pub const RTM_MISS: c_int = 0x7;
pub const RTM_NEWADDR: c_int = 0xc;
pub const RTM_NEWMADDR: c_int = 0xf;
pub const RTM_NEWMADDR2: c_int = 0x13;
pub const RTM_REDIRECT: c_int = 0x6;
pub const RTM_RESOLVE: c_int = 0xb;
pub const RTM_VERSION: c_int = 5;

#[cfg(target_os = "macos")]
const _: () = {
    assert!(RTAX_BRD == libc::RTAX_BRD);
    assert!(RTAX_DST == libc::RTAX_DST);
    assert!(RTAX_GATEWAY == libc::RTAX_GATEWAY);
    assert!(RTAX_IFP == libc::RTAX_IFP);
    assert!(RTAX_MAX == libc::RTAX_MAX);
    assert!(RTAX_NETMASK == libc::RTAX_NETMASK);
    assert!(RTA_BRD == libc::RTA_BRD);
    assert!(RTA_DST == libc::RTA_DST);
    assert!(RTA_GATEWAY == libc::RTA_GATEWAY);
    assert!(RTA_IFA == libc::RTA_IFA);
    assert!(RTA_IFP == libc::RTA_IFP);
    assert!(RTA_NETMASK == libc::RTA_NETMASK);
    assert!(RTF_GATEWAY == libc::RTF_GATEWAY);
    assert!(RTF_IFSCOPE == libc::RTF_IFSCOPE);
    assert!(RTM_ADD == libc::RTM_ADD);
    assert!(RTM_CHANGE == libc::RTM_CHANGE);
    assert!(RTM_DELADDR == libc::RTM_DELADDR);
    assert!(RTM_DELETE == libc::RTM_DELETE);
    assert!(RTM_DELMADDR == libc::RTM_DELMADDR);
    assert!(RTM_GET == libc::RTM_GET);
    assert!(RTM_GET2 == libc::RTM_GET2);
    assert!(RTM_IFINFO == libc::RTM_IFINFO);
    assert!(RTM_IFINFO2 == libc::RTM_IFINFO2);
    assert!(RTM_LOCK == libc::RTM_LOCK);
    assert!(RTM_LOSING == libc::RTM_LOSING);
    assert!(RTM_MISS == libc::RTM_MISS);
    assert!(RTM_NEWADDR == libc::RTM_NEWADDR);
    assert!(RTM_NEWMADDR == libc::RTM_NEWMADDR);
    assert!(RTM_NEWMADDR2 == libc::RTM_NEWMADDR2);
    assert!(RTM_REDIRECT == libc::RTM_REDIRECT);
    assert!(RTM_RESOLVE == libc::RTM_RESOLVE);
    assert!(RTM_VERSION == libc::RTM_VERSION);
};
