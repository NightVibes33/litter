# Local netdev compatibility patch

Upstream: netdev 0.45.0 from crates.io, MIT license retained.

Darwin IPv6 address flag queries use the same in6_ifreq ABI on iOS as macOS.
libc 0.2.190 exports this type only for macOS. Define the iOS request locally
using XNU bsd/netinet6/in6_var.h (34 uint64_t counters in the largest union
member). Preserve the 288-byte ioctl buffer, real query, flags and socket cleanup.
macOS keeps its libc type; other platform backends are unchanged.

The standalone iOS checker compiles this source with the production libc pin.
