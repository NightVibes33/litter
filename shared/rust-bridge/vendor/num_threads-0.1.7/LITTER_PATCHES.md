# Apple thread-count compatibility

Source: crates.io `num_threads` 0.1.7, registry SHA-256
`5c7398b9c8b70908f6371f47ed36737907c87c52af34c268fed0bf0ceb92ead9`.
Upstream: https://github.com/jhpratt/num_threads. MIT and Apache-2.0 licenses
are retained with the unchanged platform implementations.

libc 0.2.190 restricts its deprecated `mach_task_self()` Rust helper and
`mach_task_self_` declaration to macOS. The Apple implementation now declares
the existing libSystem `mach_task_self_` port variable directly, using libc's
`mach_port_t`, alongside its existing Mach declarations. This preserves the
same task port, thread enumeration, and port/memory cleanup on iOS without
downgrading libc or returning an artificial thread count.

The Rust workflow checks this crate against the locked libc for
`aarch64-apple-ios`. The full unsigned build must also pass to validate linking
with the iOS SDK and app archive.
