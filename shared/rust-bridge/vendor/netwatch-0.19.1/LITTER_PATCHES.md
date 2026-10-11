# Local netwatch compatibility patch

Upstream netwatch 0.19.1, Git source revision
051ab8761006d7f2155e34a49f6bb881b582d5ab. MIT/Apache-2.0
license texts are included from that revision (the registry archive omits them).

libc 0.2.190 limits Darwin routing constants to macOS even though this
crate already shares its routing parser with iOS. Restore only the constants
used by that existing iOS parser from Apple XNU bsd/net/route.h. macOS and
other BSD systems continue using libc; macOS compile-time assertions also
check each local Darwin constant against libc. No monitoring/query path is
stubbed or disabled. sysctl errors retain upstream's handling.
